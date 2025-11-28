import { NextResponse } from 'next/server';
import fs from 'node:fs';
import path from 'node:path';

export const GET = async () => {
  const configPath = process.env.DEMO_CONFIG_PATH;

  if (!configPath) {
    return NextResponse.json({ error: 'DEMO_CONFIG_PATH not set' }, { status: 400 });
  }

  try {
    // Ensure the path is absolute or resolve it relative to cwd
    const resolvedPath = path.isAbsolute(configPath)
      ? configPath
      : path.resolve(process.cwd(), configPath);

    if (!fs.existsSync(resolvedPath)) {
      return NextResponse.json({ error: 'Config file not found' }, { status: 404 });
    }

    const fileContent = fs.readFileSync(resolvedPath, 'utf8');
    const json = JSON.parse(fileContent);

    return NextResponse.json(json);
  } catch (error) {
    console.error('Error reading demo config:', error);
    return NextResponse.json({ error: 'Failed to read config file' }, { status: 500 });
  }
};
