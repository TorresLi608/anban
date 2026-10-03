import { cp } from 'node:fs/promises';

// Include browser assets so `npm start` works without a separate static server.
await cp('.next/static', '.next/standalone/.next/static', { recursive: true });
