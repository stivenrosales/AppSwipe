# Diseño: app-swipe — Window Switcher minimalista para macOS

- **Fecha:** 2026-06-18
- **Estado:** Aprobado
- **Tipo:** App nativa de macOS, construida desde cero (NO fork de AltTab)

---

## 1. Visión

Un window switcher minimalista y nativo para macOS. El usuario mantiene **Option**, pulsa **Tab** para recorrer una **lista vertical** de sus ventanas abiertas, y suelta **Option** para saltar a la ventana elegida. Rápido, ligero, premium.

## 2. Motivo (por qué desde cero, no fork)

El objetivo es **control total del código y entenderlo al 100%**. Forkear AltTab contradice eso: es un proyecto Swift grande y maduro, con **APIs privadas de macOS** (`PrivateApis.swift`) para capturar thumbnails, ventana de preferencias multi-tab, y ahora una versión Pro comercial. Heredar esa complejidad es lo opuesto a control total.

Dato relevante: AltTab YA tiene un modo lista (estilo "Titles"). Esto confirma que el motivo no es la feature, sino el aprendizaje y el control. Por eso: **MVP propio, minimalista.**

## 3. Stack

- **Lenguaje:** Swift.
- **UI:** SwiftUI para la lista (modelo declarativo, familiar viniendo de React/Angular).
- **Sistema:** AppKit donde SwiftUI no llega (`NSPanel` flotante, monitor de hotkey global, ciclo de vida de app agente).
- **Descartados:** Electron (pesado, contradice "minimalista"), Tauri (capa web innecesaria para una UI que es una lista; igual requeriría código nativo).

## 4. Decisiones de producto

1. **Una fila por VENTANA**, no por app (si hay 3 ventanas de Chrome, se ven 3 filas).
2. **Cada fila = ícono de la app + título de la ventana + nombre de la app. SIN miniaturas.** Decisión clave: las miniaturas son lo que obliga a AltTab a usar APIs privadas. Al hacer lista de texto + ícono nos mantenemos **100% en APIs públicas de Apple.**
3. **Orden MRU** (Most Recently Used): la ventana anterior siempre en la posición 2, lista para un Option+Tab rápido.
4. **Navegación:** Tab avanza ↓, Shift+Tab retrocede ↑, flechas ↑/↓, Esc cancela, click directo selecciona.
5. **Atajo:** Option+Tab (mantener Option, tabular, soltar para elegir). Cmd+Tab descartado: macOS lo reserva a nivel de sistema y el switcher nativo se cuela; interceptarlo requiere `CGEventTap` frágil.

## 5. Arquitectura — 3 capas (hexagonal ligero)

```
┌─ Presentación (SwiftUI) ──────────────────┐
│  SwitcherPanel (NSPanel flotante + blur)  │
│  WindowListView (la lista declarativa)    │
└───────────────────────────────────────────┘
┌─ Dominio (Swift puro, CERO macOS) ────────┐
│  WindowInfo (modelo)                      │
│  SwitcherController (estado + navegación) │  ← testeable al 100%
│  Protocols: WindowProvider, WindowActivator│  ← los "puertos"
└───────────────────────────────────────────┘
┌─ Sistema (Adapters — el "mundo sucio") ───┐
│  CGWindowEnumerator  (lista ventanas)     │
│  AXWindowActivator   (trae al frente)     │
│  HotKeyMonitor       (Option+Tab+release) │
│  AccessibilityGate   (permisos)           │
└───────────────────────────────────────────┘
```

El dominio depende de **protocolos** (puertos), no de macOS. Los adapters los implementan. La lógica de navegación se testea sin abrir una sola ventana.

### APIs públicas usadas
- **Enumerar ventanas:** `CGWindowListCopyWindowInfo` (z-order, títulos, owner PID) + Accessibility API (`AXUIElementCreateApplication` → `kAXWindowsAttribute`).
- **Activar ventana:** `AXUIElementPerformAction(window, kAXRaiseAction)` + `NSRunningApplication.activate`.
- **Hotkey:** monitor de eventos global (`NSEvent` / `CGEventTap`) para detectar Option mantenido + Tab + release de Option (`flagsChanged`).
- **Permiso:** `AXIsProcessTrustedWithOptions`.

## 6. Flujo de datos

1. Mantener Option + pulsar Tab → `HotKeyMonitor` detecta.
2. `SwitcherController` pide ventanas a `WindowProvider` → ordena por MRU.
3. Aparece `SwitcherPanel` con selección en posición 2 (la anterior).
4. Cada Tab adicional (con Option presionado) baja la selección.
5. Soltar Option → `AXWindowActivator` trae la ventana al frente → panel desaparece.
6. Esc → cancela, nada cambia.

## 7. Permisos y casos borde

- Requiere **permiso de Accesibilidad**. Onboarding: si falta, abrir el panel correcto de Ajustes del Sistema.
- Cero ventanas → no aparece el panel.
- App agente (`LSUIElement = true`): sin ícono en el Dock, vive invisible.
- App muere mientras está listada → manejar al activar (no crashear).

## 8. Testing (Strict TDD)

- Dominio puro (`SwitcherController`, orden MRU, navegación) → tests XCTest mockeando los protocolos. **Rojo primero, luego implementación.**
- Adapters de macOS → verificación manual (tocan el sistema real).

## 9. Alcance del MVP

| ✅ En el MVP | ❌ Fuera (por ahora) |
|---|---|
| Option+Tab, lista vertical | Miniaturas en vivo |
| Ícono + título + app | Multi-monitor avanzado |
| Orden MRU | Ventanas minimizadas |
| Activar ventana | Filtro al escribir (fase 2) |
| Permisos + onboarding | Panel de preferencias |
