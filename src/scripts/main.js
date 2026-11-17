
import "./lightbox.js";

// Estado compartido
let lastScrollY = window.scrollY;

// --- 1. MENÚ MÓVIL ---
document.addEventListener("click", (event) => {
  const target = event.target;

  if (!(target instanceof Element)) return;

  const button = target.closest("#menu-toggle");
  if (!button) return;

  event.preventDefault();

  const menu = document.getElementById("menu");
  if (!menu) return;

  const isOpen = button.getAttribute("aria-expanded") === "true";
  const nextState = !isOpen;

  button.setAttribute("aria-expanded", String(nextState));
  button.setAttribute(
    "aria-label",
    nextState ? "Cerrar menú" : "Abrir menú"
  );

  menu.classList.toggle("hidden", !nextState);
});

// --- 2. SCROLL: MENÚ Y HEADER ---
window.addEventListener(
  "scroll",
  () => {
    // Cerrar menú al hacer scroll
    const menu = document.getElementById("menu");
    const button = document.getElementById("menu-toggle");

    if (menu && button && !menu.classList.contains("hidden")) {
      menu.classList.add("hidden");
      button.setAttribute("aria-expanded", "false");
      button.setAttribute("aria-label", "Abrir menú");
    }

    // Ocultar o mostrar header según la dirección del scroll
    const header = document.getElementById("main-header");

    if (header) {
      if (window.scrollY > lastScrollY && window.scrollY > 100) {
        header.classList.add("header-hidden");
      } else {
        header.classList.remove("header-hidden");
      }
    }

    lastScrollY = window.scrollY;
  },
  { passive: true }
);

// --- 3. REINICIAR ESTADO EN CADA NAVEGACIÓN ---
document.addEventListener("astro:page-load", () => {
  const menu = document.getElementById("menu");
  const button = document.getElementById("menu-toggle");

  if (menu && button) {
    menu.classList.add("hidden");
    button.setAttribute("aria-expanded", "false");
    button.setAttribute("aria-label", "Abrir menú");
  }

  lastScrollY = window.scrollY;

  const header = document.getElementById("main-header");
  header?.classList.remove("header-hidden");
});

// --- 4. PROTECCIÓN DE IMÁGENES ---
const isImageTarget = (target) => {
  if (!(target instanceof Element)) return false;

  return (
    target instanceof HTMLImageElement ||
    target.closest("img") !== null
  );
};

// Bloquear menú contextual
document.addEventListener("contextmenu", (event) => {
  if (isImageTarget(event.target)) {
    event.preventDefault();
  }
});

// Bloquear arrastre de imágenes
document.addEventListener("dragstart", (event) => {
  if (isImageTarget(event.target)) {
    event.preventDefault();
  }
});

// Seguimiento de pulsación prolongada en móviles
let touchTimer;

document.addEventListener(
  "touchstart",
  (event) => {
    if (!isImageTarget(event.target)) return;

    clearTimeout(touchTimer);

    touchTimer = window.setTimeout(() => {
      touchTimer = undefined;
    }, 500);
  },
  { passive: true }
);

document.addEventListener("touchend", () => {
  clearTimeout(touchTimer);
});

document.addEventListener("touchmove", () => {
  clearTimeout(touchTimer);
});
