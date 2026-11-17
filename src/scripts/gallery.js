
import justifiedLayout from "./justified-layout.js";

/**
 * Inicializa una galería justificada.
 *
 * @param {HTMLElement|string} gallery
 * @param {Object} options
 * @returns {Function} función para limpiar la galería
 */
export function initJustifiedGallery(gallery, options = {}) {
  const element =
    typeof gallery === "string"
      ? document.querySelector(gallery)
      : gallery;

  if (!(element instanceof HTMLElement)) {
    return () => {};
  }

  const {
    itemSelector = ".gallery-item",
    targetRowHeight = 288,
    spacing = 8,
    heightTolerance = 0.25,
  } = options;

  const items = Array.from(element.querySelectorAll(itemSelector));

  if (!items.length) {
    return () => {};
  }

  // Guardamos los estilos originales para poder restaurarlos.
  const originalStyles = new Map();

  const properties = [
    "position",
    "width",
    "height",
    "top",
    "left",
    "overflow",
  ];

  const saveStyles = (node, props) => {
    if (originalStyles.has(node)) return;

    const styles = {};

    props.forEach((property) => {
      styles[property] = node.style[property];
    });

    originalStyles.set(node, styles);
  };

  const getAspectRatio = (item) => {
    const img = item.querySelector("img");

    if (!img) return 1;

    const width =
      Number.parseFloat(img.getAttribute("width")) ||
      img.naturalWidth;

    const height =
      Number.parseFloat(img.getAttribute("height")) ||
      img.naturalHeight;

    if (
      !Number.isFinite(width) ||
      !Number.isFinite(height) ||
      width <= 0 ||
      height <= 0
    ) {
      return 1;
    }

    return width / height;
  };

  let containerWidth = 0;
  let resizeObserver;

  const updateGallery = () => {
    const width = element.getBoundingClientRect().width;

    if (!width || Math.abs(width - containerWidth) < 0.5) {
      return;
    }

    containerWidth = width;

    const aspectRatios = items.map(getAspectRatio);

    const layout = justifiedLayout(aspectRatios, {
      rowWidth: width,
      spacing,
      rowHeight: targetRowHeight,
      heightTolerance,
    });

    saveStyles(element, ["position", "height", "visibility"]);

    element.style.position = "relative";
    element.style.visibility = "hidden";

    items.forEach((item, index) => {
      const box = layout.boxes[index];

      if (!box) return;

      const { width: boxWidth, height, top, left } = box;

      saveStyles(item, properties);

      item.style.position = "absolute";
      item.style.width = `${boxWidth}px`;
      item.style.height = `${height}px`;
      item.style.top = `${top}px`;
      item.style.left = `${left}px`;
      item.style.overflow = "hidden";

      const img = item.querySelector("img");

      if (img) {
        saveStyles(img, ["width", "height", "objectFit", "display"]);

        img.style.width = "100%";
        img.style.height = "100%";
        img.style.objectFit = "contain";
        img.style.display = "block";
      }
    });

    element.style.height = `${layout.containerHeight}px`;
    element.style.visibility = "";
  };

  if ("ResizeObserver" in window) {
    resizeObserver = new ResizeObserver(updateGallery);
    resizeObserver.observe(element);
  } else {
    window.addEventListener("resize", updateGallery);
    window.addEventListener("orientationchange", updateGallery);
  }

  updateGallery();

  return () => {
    resizeObserver?.disconnect();

    window.removeEventListener("resize", updateGallery);
    window.removeEventListener("orientationchange", updateGallery);

    originalStyles.forEach((styles, node) => {
      Object.entries(styles).forEach(([property, value]) => {
        node.style[property] = value;
      });
    });
  };
}
