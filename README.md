
# Marta Rodriguez Palau — Photography Portfolio

Portfolio fotográfico de Marta Rodriguez Palau. Un espacio web independiente construido con Astro para presentar proyectos de fotografía, galerías y trabajo visual.

**Web:** [martarodriguezpalau.org](https://martarodriguezpalau.org)

---

## Sobre el proyecto

Este proyecto es un portfolio fotográfico personal concebido como un espacio propio en internet para presentar el trabajo de Marta Rodriguez Palau.

La web reúne proyectos fotográficos, galerías y una sección biográfica con información curricular. Su diseño prioriza las imágenes, la navegación sencilla y una presentación visual limpia.

El sitio está desarrollado con tecnologías web estáticas y utiliza una estructura de contenidos basada en Astro y Markdown. Está disponible en catalán, español e inglés.

## Objetivos

- **Portfolio fotográfico:** presentar proyectos y series de fotografía.
- **Archivo visual:** organizar y conservar galerías de imágenes.
- **Identidad propia:** disponer de una presencia digital independiente y personalizable.
- **Multilingüismo:** ofrecer contenidos en catalán, español e inglés.
- **Autonomía digital:** mantener el control sobre la publicación y presentación del trabajo.
- **Sostenibilidad:** utilizar tecnologías ligeras y de bajo mantenimiento.

## Tecnologías

- [Astro](https://astro.build/) — generador de sitios web.
- [Sass](https://sass-lang.com/) — preprocesador CSS.
- JavaScript — interacciones y funcionalidades del sitio.
- Markdown — gestión de proyectos y contenidos biográficos.
- [PhotoSwipe](https://photoswipe.com/) — visualización de imágenes.
- [Cloudflare Workers](https://developers.cloudflare.com/workers/) — infraestructura prevista para el despliegue.
- Cloudflare R2 — almacenamiento externo de imágenes previsto para el proyecto.
- [GitHub](https://github.com/) — control de versiones y repositorio del proyecto.

## Estructura del proyecto

```text
Astro-Portfolio-Martarodpal/
├── public/
│   ├── fonts/                 # Tipografías
│   ├── images/                # Recursos estáticos
│   └── favicon.*              # Iconos del sitio
│
├── src/
│   ├── components/            # Componentes reutilizables
│   ├── content/
│   │   ├── bio/               # Biografía y CV
│   │   └── work/              # Proyectos y galerías
│   │
│   ├── data/                  # Manifiesto de imágenes
│   ├── i18n/                  # Traducciones y utilidades lingüísticas
│   ├── layouts/               # Estructuras generales de página
│   ├── pages/                 # Rutas y páginas Astro
│   ├── scripts/               # JavaScript y galerías
│   ├── styles/                # Estilos SCSS y CSS
│   └── utils/                 # Funciones auxiliares
│
├── scripts/
│   └── generate-media-manifest.js
│
├── astro.config.mjs           # Configuración de Astro
├── package.json               # Dependencias y scripts
├── package-lock.json          # Versiones bloqueadas
├── tsconfig.json
├── wrangler.jsonc             # Configuración de Cloudflare
└── README.md
```

## Desarrollo local

### Requisitos

- Node.js 22.23.4 o superior.
- npm.

### Instalación

Clonar el repositorio:

```bash
git clone <URL_DEL_REPOSITORIO>
cd Astro-Portfolio-Martarodpal
```

Instalar las dependencias:

```bash
npm ci
```

Iniciar el servidor de desarrollo:

```bash
npm run dev
```

Astro estará disponible normalmente en:

```text
http://localhost:4321
```

### Compilación

Generar la versión de producción:

```bash
npm run build
```

Los archivos generados se guardan en `dist/`.

Para previsualizar la compilación:

```bash
npm run preview
```

## Gestión de contenidos

El contenido se organiza mediante colecciones de Astro y archivos Markdown.

### Proyectos y galerías

Los proyectos y galerías se almacenan en:

```text
src/content/work/
```

Cada proyecto tiene su propio directorio, que contiene el archivo Markdown con sus metadatos y las referencias a sus imágenes.

Las galerías se identifican mediante el campo `type: gallery` en el frontmatter. Los proyectos convencionales utilizan el tipo `project`.

### Biografía y CV

Los contenidos biográficos se encuentran en:

```text
src/content/bio/
```

Incluyen las versiones lingüísticas de la biografía y la información curricular.

### Idiomas

El sitio trabaja con tres idiomas:

- Catalán (`ca`)
- Español (`es`)
- Inglés (`en`)

Las traducciones de la interfaz se gestionan en `src/i18n/`, mientras que los contenidos biográficos utilizan archivos Markdown específicos para cada idioma.

## Gestión de imágenes

El proyecto utiliza un manifiesto de medios para registrar las imágenes y sus dimensiones.

El manifiesto se genera mediante:

```bash
npm run generate:media
```

Este proceso recorre los contenidos de `src/content/` y actualiza:

```text
src/data/media-manifest.json
```

La generación del manifiesto también se ejecuta automáticamente antes de iniciar el servidor de desarrollo mediante `predev`.

Las imágenes están previstas para alojarse en Cloudflare R2 y servirse a través del dominio de medios del proyecto.

## Despliegue

El proyecto está preparado para utilizar **Cloudflare Workers mediante Static Assets**.

El proceso de publicación contempla:

- GitHub como repositorio de código.
- Astro para generar los archivos estáticos en `dist/`.
- Wrangler para gestionar los despliegues.
- Cloudflare Workers para servir el sitio.
- Cloudflare R2 para el almacenamiento de imágenes.

La configuración definitiva del almacenamiento, el dominio de medios y el despliegue se completará durante la puesta en producción.

## Derechos de autor

Las fotografías, textos y demás contenidos originales de este sitio son propiedad de Marta Rodriguez Palau, salvo que se indique expresamente lo contrario.

Su reproducción, distribución o utilización requiere autorización previa.

Las herramientas y dependencias de terceros conservan sus respectivas licencias.

---

© Marta Rodriguez Palau
