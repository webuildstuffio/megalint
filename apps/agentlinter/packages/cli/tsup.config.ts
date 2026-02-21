import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/bin.ts'],
  format: ['cjs'],
  target: 'node18',
  clean: true,
  minify: true,
  noExternal: [/(.*)/], // Bundle everything
});
