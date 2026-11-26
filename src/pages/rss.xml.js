
import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';

export async function GET(context) {
  // Obtener los proyectos y galerías.
  const work = await getCollection('work');

  // Excluir borradores y contenidos sin fecha.
  const publishedItems = work.filter(
    (item) =>
      !item.data.draft &&
      item.data.date instanceof Date &&
      item.data.type !== 'gallery'
  );

  // Convertir los contenidos al formato RSS.
  const rssItems = publishedItems.map((item) => ({
    title: item.data.title,
    description: Array.isArray(item.data.description)
      ? item.data.description.join(' ')
      : item.data.description || '',
    pubDate: item.data.date,
    link: `/work/${item.id}`,
  }));

  // Ordenar cronológicamente, del más reciente al más antiguo.
  rssItems.sort(
    (a, b) => b.pubDate.valueOf() - a.pubDate.valueOf()
  );

  // Generar el feed RSS.
  return rss({
    title: 'Marta Rodriguez Palau',
    description: 'Portfolio de fotografía de Marta Rodriguez Palau',
    site: context.site,
    items: rssItems,
    customData: '<language>ca-ES</language>',
  });
}
