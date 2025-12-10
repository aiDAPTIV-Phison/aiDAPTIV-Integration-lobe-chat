import type {
  AiProviderDetailItem,
  AiProviderListItem,
  AiProviderRuntimeConfig,
  CreateAiProviderParams,
  UpdateAiProviderConfigParams,
} from '@lobechat/types';
import { and, asc, desc, eq } from 'drizzle-orm';
import { isEmpty } from 'lodash-es';
import { ModelProvider } from 'model-bank';

import { DEFAULT_MODEL_PROVIDER_LIST } from '@/config/modelProviders';
import { merge } from '@/utils/merge';

import { AiProviderSelectItem, aiModels, aiProviders } from '../schemas';
import { LobeChatDatabase } from '../type';

type DecryptUserKeyVaults = (encryptKeyVaultsStr: string | null) => Promise<any>;

type EncryptUserKeyVaults = (keyVaults: string) => Promise<string>;

export class AiProviderModel {
  private userId: string;
  private db: LobeChatDatabase;

  constructor(db: LobeChatDatabase, userId: string) {
    this.userId = userId;
    this.db = db;
  }

  create = async (
    { keyVaults: userKey, ...params }: CreateAiProviderParams,
    encryptor?: EncryptUserKeyVaults,
  ) => {
    // eslint-disable-next-line unicorn/consistent-function-scoping
    const defaultSerialize = (s: string) => s;
    const encrypt = encryptor ?? defaultSerialize;
    const keyVaults = await encrypt(JSON.stringify(userKey));

    const [result] = await this.db
      .insert(aiProviders)
      .values({
        ...params,
        // each new ai provider we will set it to enabled by default
        enabled: true,
        keyVaults,
        userId: this.userId,
      })
      .returning();

    return result;
  };

  delete = async (id: string) => {
    return this.db.transaction(async (trx) => {
      // 1. delete all models of the provider
      await trx
        .delete(aiModels)
        .where(and(eq(aiModels.providerId, id), eq(aiModels.userId, this.userId)));

      // 2. delete the provider
      await trx
        .delete(aiProviders)
        .where(and(eq(aiProviders.id, id), eq(aiProviders.userId, this.userId)));
    });
  };

  deleteAll = async () => {
    return this.db.delete(aiProviders).where(eq(aiProviders.userId, this.userId));
  };

  query = async () => {
    return this.db.query.aiProviders.findMany({
      orderBy: [desc(aiProviders.updatedAt)],
      where: eq(aiProviders.userId, this.userId),
    });
  };

  getAiProviderList = async (): Promise<AiProviderListItem[]> => {
    const result = await this.db
      .select({
        description: aiProviders.description,
        enabled: aiProviders.enabled,
        id: aiProviders.id,
        logo: aiProviders.logo,
        name: aiProviders.name,
        sort: aiProviders.sort,
        source: aiProviders.source,
      })
      .from(aiProviders)
      .where(eq(aiProviders.userId, this.userId))
      .orderBy(asc(aiProviders.sort), desc(aiProviders.updatedAt));

    return result as AiProviderListItem[];
  };

  findById = async (id: string) => {
    return this.db.query.aiProviders.findFirst({
      where: and(eq(aiProviders.id, id), eq(aiProviders.userId, this.userId)),
    });
  };

  update = async (id: string, value: Partial<AiProviderSelectItem>) => {
    return this.db
      .update(aiProviders)
      .set({ ...value, updatedAt: new Date() })
      .where(and(eq(aiProviders.id, id), eq(aiProviders.userId, this.userId)));
  };

  updateConfig = async (
    id: string,
    value: UpdateAiProviderConfigParams,
    encryptor?: EncryptUserKeyVaults,
  ) => {
    // eslint-disable-next-line unicorn/consistent-function-scoping
    const defaultSerialize = (s: string) => s;
    const encrypt = encryptor ?? defaultSerialize;
    const keyVaults = await encrypt(JSON.stringify(value.keyVaults));

    const commonFields = {
      checkModel: value.checkModel,
      config: value.config,
      fetchOnClient: value.fetchOnClient,
      keyVaults,
    };

    return this.db
      .insert(aiProviders)
      .values({
        ...commonFields,
        id,
        source: this.getProviderSource(id),
        userId: this.userId,
      })
      .onConflictDoUpdate({
        set: commonFields,
        target: [aiProviders.id, aiProviders.userId],
      });
  };

  toggleProviderEnabled = async (id: string, enabled: boolean) => {
    return this.db
      .insert(aiProviders)
      .values({
        enabled,
        id,
        source: this.getProviderSource(id),
        updatedAt: new Date(),
        userId: this.userId,
      })
      .onConflictDoUpdate({
        set: { enabled },
        target: [aiProviders.id, aiProviders.userId],
      });
  };

  updateOrder = async (sortMap: { id: string; sort: number }[]) => {
    await this.db.transaction(async (tx) => {
      const updates = sortMap.map(({ id, sort }) => {
        return tx
          .insert(aiProviders)
          .values({
            enabled: true,
            id,
            sort,
            source: this.getProviderSource(id),
            updatedAt: new Date(),
            userId: this.userId,
          })
          .onConflictDoUpdate({
            set: { sort, updatedAt: new Date() },
            target: [aiProviders.id, aiProviders.userId],
          });
      });

      await Promise.all(updates);
    });
  };

  getAiProviderById = async (
    id: string,
    decryptor?: DecryptUserKeyVaults,
    encryptor?: EncryptUserKeyVaults,
  ): Promise<AiProviderDetailItem | undefined> => {
    const query = this.db
      .select({
        checkModel: aiProviders.checkModel,
        config: aiProviders.config,
        description: aiProviders.description,
        enabled: aiProviders.enabled,
        fetchOnClient: aiProviders.fetchOnClient,
        id: aiProviders.id,
        keyVaults: aiProviders.keyVaults,
        logo: aiProviders.logo,
        name: aiProviders.name,
        settings: aiProviders.settings,
        source: aiProviders.source,
      })
      .from(aiProviders)
      .where(and(eq(aiProviders.id, id), eq(aiProviders.userId, this.userId)))
      .limit(1);

    const [result] = await query;

    if (!result) {
      // if the provider is builtin but not init, we will insert it to the db
      if (this.isBuiltInProvider(id)) {
        let keyVaults = null;
        if (id === 'openai' && encryptor) {
          const baseURL = process.env.OPENAI_PROXY_URL || 'http://127.0.0.1:13141/v1';
          // In Demo mode, set a default API key if not provided
          const apiKey =
            process.env.OPENAI_API_KEY ||
            (baseURL !== 'https://api.openai.com/v1' ? 'None' : undefined);
          const keyVaultsData: { apiKey?: string; baseURL: string } = { baseURL };
          if (apiKey) {
            keyVaultsData.apiKey = apiKey;
          }
          keyVaults = await encryptor(JSON.stringify(keyVaultsData));
        }

        await this.db.insert(aiProviders).values({
          id,
          keyVaults,
          source: 'builtin',
          userId: this.userId,
        });

        const resultAgain = await query;

        return { ...resultAgain[0] } as unknown as AiProviderDetailItem;
      }

      return;
    }

    const decrypt = decryptor ?? JSON.parse;

    let keyVaults = {};

    if (!!result.keyVaults) {
      try {
        keyVaults = await decrypt(result.keyVaults);
      } catch {
        /* empty */
      }
    }

    // In Demo mode, check if OPENAI_PROXY_URL is set and update if needed
    // This ensures .env OPENAI_PROXY_URL takes precedence over database values
    if (id === 'openai' && encryptor) {
      // Use environment variable or default Demo mode URL
      const envBaseURL = process.env.OPENAI_PROXY_URL || 'http://127.0.0.1:13141/v1';
      const currentBaseURL = (keyVaults as { apiKey?: string; baseURL?: string })?.baseURL;
      const currentApiKey = (keyVaults as { apiKey?: string; baseURL?: string })?.apiKey;

      // Set default API key in Demo mode if not already set
      // If OPENAI_PROXY_URL is set to a non-default value, use 'None' as default API key
      const defaultApiKey =
        process.env.OPENAI_API_KEY ||
        (envBaseURL !== 'https://api.openai.com/v1' ? 'None' : undefined);
      const shouldUpdateApiKey = !currentApiKey || currentApiKey.trim() === '';

      // Update if the baseURL or API key needs to be updated
      // Always update in Demo mode (when baseURL is not the default OpenAI URL)
      // Also update if baseURL is missing or different, or if API key is missing
      const needsUpdate =
        envBaseURL !== 'https://api.openai.com/v1' &&
        (currentBaseURL !== envBaseURL ||
          !currentBaseURL ||
          shouldUpdateApiKey ||
          (envBaseURL === 'http://127.0.0.1:13141/v1' &&
            (!currentApiKey || currentApiKey.trim() === '')));

      if (needsUpdate) {
        const updatedKeyVaultsData = {
          ...keyVaults,
          apiKey:
            shouldUpdateApiKey && defaultApiKey ? defaultApiKey : currentApiKey || defaultApiKey,
          baseURL: envBaseURL,
        };

        const updatedKeyVaults = await encryptor(JSON.stringify(updatedKeyVaultsData));

        await this.db
          .update(aiProviders)
          .set({ keyVaults: updatedKeyVaults, updatedAt: new Date() })
          .where(and(eq(aiProviders.id, id), eq(aiProviders.userId, this.userId)));

        // Update keyVaults to reflect the new value
        keyVaults = updatedKeyVaultsData;
      }
    }

    return {
      ...result,
      fetchOnClient: typeof result.fetchOnClient === 'boolean' ? result.fetchOnClient : undefined,
      keyVaults,
      settings: isEmpty(result.settings) ? undefined : result.settings,
    } as AiProviderDetailItem;
  };

  getAiProviderRuntimeConfig = async (decryptor?: DecryptUserKeyVaults) => {
    const result = await this.db
      .select({
        config: aiProviders.config,
        fetchOnClient: aiProviders.fetchOnClient,
        id: aiProviders.id,
        keyVaults: aiProviders.keyVaults,
        settings: aiProviders.settings,
      })
      .from(aiProviders)
      .where(and(eq(aiProviders.userId, this.userId)));

    const decrypt = decryptor ?? JSON.parse;
    let runtimeConfig: Record<string, AiProviderRuntimeConfig> = {};

    for (const item of result) {
      const builtin = DEFAULT_MODEL_PROVIDER_LIST.find((provider) => provider.id === item.id);

      const userSettings = item.settings || {};

      let keyVaults: Record<string, any> = {};
      if (!!item.keyVaults) {
        try {
          keyVaults = await decrypt(item.keyVaults);
        } catch {
          /* empty */
        }
      }

      if (item.id === 'openai') {
        const envBaseURL = process.env.OPENAI_PROXY_URL || 'http://127.0.0.1:13141/v1';
        const currentBaseURL = (keyVaults as { baseURL?: string }).baseURL;
        const currentApiKey = (keyVaults as { apiKey?: string }).apiKey;
        const defaultApiKey =
          process.env.OPENAI_API_KEY ||
          (envBaseURL !== 'https://api.openai.com/v1' ? 'None' : undefined);

        const shouldUpdateBaseURL = !currentBaseURL || currentBaseURL !== envBaseURL;
        const shouldUpdateApiKey = !currentApiKey || currentApiKey.trim() === '';

        if (shouldUpdateBaseURL || shouldUpdateApiKey) {
          keyVaults = {
            ...keyVaults,
            apiKey:
              shouldUpdateApiKey && defaultApiKey ? defaultApiKey : currentApiKey || defaultApiKey,
            baseURL: envBaseURL,
          };
        }
      }

      runtimeConfig[item.id] = {
        config: item.config || {},
        fetchOnClient: typeof item.fetchOnClient === 'boolean' ? item.fetchOnClient : undefined,
        keyVaults,
        settings: !!builtin ? merge(builtin.settings, userSettings) : userSettings,
      };
    }

    return runtimeConfig;
  };

  private isBuiltInProvider = (id: string) => Object.values(ModelProvider).includes(id as any);

  private getProviderSource = (id: string) => (this.isBuiltInProvider(id) ? 'builtin' : 'custom');
}
