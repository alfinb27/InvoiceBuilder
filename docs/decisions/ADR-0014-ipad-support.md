# ADR-0014: iPad support

- **Status:** Accepted
- **Date:** 2026-09-19

## Decision
Universal iPhone + iPad app designed from Phase 1: `TabView` `.sidebarAdaptable` + `NavigationSplitView`;
two-pane builder (form + live PDF preview) in regular width; keyboard shortcuts (⌘N, ⇧⌘N, ⌘F, ⌘P, ⌘↩), focus
order, menu-bar commands; pointer hover, context menus, drag and drop; PencilKit signature; AirPrint.
v1 is single-window but fully resizable (iPadOS 26 windowing): layouts work at any width and navigation state
survives size-class changes. Android tablets/foldables get the equivalent (Material 3 Adaptive) in Phase 7.
Mac ("Designed for iPad") is decided by a one-day check at the Phase 6 gate.

## Revisit when
iPad work exceeds ~12 days → fully adapt only builder, list and preview.
