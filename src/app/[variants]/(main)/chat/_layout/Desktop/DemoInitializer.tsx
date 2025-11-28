'use client';

import { useEffect, useRef } from 'react';

import { useSessionStore } from '@/store/session';

const DemoInitializer = () => {
  const createSession = useSessionStore((s) => s.createSession);
  const initialized = useRef(false);

  useEffect(() => {
    const initDemo = async () => {
      // Check if demo mode is enabled via env var
      if (process.env.NEXT_PUBLIC_DEMO_MODE !== 'true') return;

      // Check if we already initialized in this browser session to avoid creating duplicates on refresh
      if (sessionStorage.getItem('demo_initialized')) return;

      // Prevent double execution in React Strict Mode
      if (initialized.current) return;
      initialized.current = true;

      try {
        const res = await fetch('/api/demo/config');
        if (!res.ok) return;

        const data = await res.json();

        // Extract systemRole and openingMessage from the JSON structure
        // Assuming the structure matches the provided example:
        // state.sessions[0].config
        const sessionConfig = data?.state?.sessions?.[0]?.config;

        if (sessionConfig) {
          const { systemRole, openingMessage, model, provider, plugins } = sessionConfig;

          const newSession: any = {
            config: {
              model,
              openingMessage,
              plugins,
              provider,
              systemRole,
            },
          };

          await createSession(newSession, true);
          sessionStorage.setItem('demo_initialized', 'true');
        }
      } catch (error) {
        console.error('Failed to initialize demo session:', error);
      }
    };

    initDemo();
  }, []);

  return null;
};

export default DemoInitializer;
