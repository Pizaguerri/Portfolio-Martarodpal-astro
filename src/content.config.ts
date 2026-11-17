
import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

// Categorías del CV
const cvSchema = z.object({
  exposicions: z.array(z.string()).optional().default([]),
  llibres: z.array(z.string()).optional().default([]),
  premis: z.array(z.string()).optional().default([]),
  'col·laboracions': z.array(z.string()).optional().default([]),
});

// Campos comunes
const portfolioSchema = z.object({
  title: z.string(),
  description: z.string().optional(),
  date: z.coerce.date().optional(),
  tags: z.array(z.string()).optional().default([]),
  summary: z.string().optional(),
  draft: z.boolean().optional().default(false),
});

// Projects
const projects = defineCollection({
  loader: glob({
    pattern: '**/*.md',
    base: './src/content/projects',
    generateId: ({ entry }) =>
      entry.replace(/\/index\.([a-z]{2})\.md$/, '.$1'),
  }),
  schema: portfolioSchema.extend({
    cv: cvSchema.default({
      exposicions: [],
      llibres: [],
      premis: [],
      'col·laboracions': [],
    }),
  }),
});

// Blog (se mantiene la colección original, aunque Marta no la utiliza)

// Selected
const selected = defineCollection({
  loader: glob({
    pattern: '**/*.md',
    base: './src/content/selected',
    generateId: ({ entry }) =>
      entry.replace(/\/index\.([a-z]{2})\.md$/, '.$1'),
  }),
  schema: portfolioSchema,
});

// About y CV manual
const about = defineCollection({
  loader: glob({
    pattern: '*.md',
    base: './src/content/about',
    generateId: ({ entry }) =>
      entry.replace(/\.([a-z]{2})\.md$/, '.$1'),
  }),
  schema: z.object({
    title: z.string().optional(),
    exposicions: z.array(z.string()).optional().default([]),
    llibres: z.array(z.string()).optional().default([]),
    premis: z.array(z.string()).optional().default([]),
    'col·laboracions': z.array(z.string()).optional().default([]),
  }).passthrough(),
});

export const collections = {
  projects,
  selected,
  about,
};
