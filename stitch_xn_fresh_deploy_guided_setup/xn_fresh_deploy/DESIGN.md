---
name: Xn Fresh Deploy
colors:
  surface: '#0b1326'
  surface-dim: '#0b1326'
  surface-bright: '#31394d'
  surface-container-lowest: '#060e20'
  surface-container-low: '#131b2e'
  surface-container: '#171f33'
  surface-container-high: '#222a3d'
  surface-container-highest: '#2d3449'
  on-surface: '#dae2fd'
  on-surface-variant: '#ccc3d8'
  inverse-surface: '#dae2fd'
  inverse-on-surface: '#283044'
  outline: '#958da1'
  outline-variant: '#4a4455'
  surface-tint: '#d2bbff'
  primary: '#d2bbff'
  on-primary: '#3f008e'
  primary-container: '#7c3aed'
  on-primary-container: '#ede0ff'
  inverse-primary: '#732ee4'
  secondary: '#4cd7f6'
  on-secondary: '#003640'
  secondary-container: '#03b5d3'
  on-secondary-container: '#00424e'
  tertiary: '#4edea3'
  on-tertiary: '#003824'
  tertiary-container: '#007650'
  on-tertiary-container: '#76ffc2'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#eaddff'
  primary-fixed-dim: '#d2bbff'
  on-primary-fixed: '#25005a'
  on-primary-fixed-variant: '#5a00c6'
  secondary-fixed: '#acedff'
  secondary-fixed-dim: '#4cd7f6'
  on-secondary-fixed: '#001f26'
  on-secondary-fixed-variant: '#004e5c'
  tertiary-fixed: '#6ffbbe'
  tertiary-fixed-dim: '#4edea3'
  on-tertiary-fixed: '#002113'
  on-tertiary-fixed-variant: '#005236'
  background: '#0b1326'
  on-background: '#dae2fd'
  surface-variant: '#2d3449'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  title-sm:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-caps:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.1em
  mono-data:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 18px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  window_padding: 24px
  gutter: 16px
---

## Brand & Style
The design system is engineered for the high-performance gaming utility market, prioritizing speed, precision, and immersive aesthetics. The brand personality is "Technical Excellence"—it feels like a high-end hardware interface rather than a standard software utility. 

The visual style blends **Modern Minimalism** with **Glassmorphism** and **High-Tech** accents. It utilizes deep, atmospheric layering to create a sense of focused immersion, ensuring the user feels in total control of their deployment environment. The UI avoids "gamer" clichés (like heavy metal textures or distressed fonts) in favor of ultra-clean lines, subtle glows, and sophisticated translucency.

## Colors
The palette is rooted in a "Deep Space" foundation, using a mix of Dark Charcoal and Deep Navy to provide a high-contrast backdrop for vibrant functional accents.

- **Primary (Deep Purple):** Used for critical interaction points, active states, and primary call-to-actions. It signifies the core "power" of the utility.
- **Secondary (Cyan):** Used for data visualization, highlights, and secondary interactive elements. It provides a high-tech "laser" feel.
- **Functional Colors:** Success (Soft Green), Warning (Amber), and Error (Red) are used with high saturation but small surface areas to maintain the dark aesthetic without visual noise.
- **Surfaces:** Backgrounds use a tiered approach from the darkest `#0B0E14` for the base to `#1E293B` for elevated interactive panels.

## Typography
The system uses **Inter** for all primary UI text to ensure maximum legibility and a modern, neutral feel. **JetBrains Mono** is introduced as a secondary typeface for labels, technical data, and status indicators to reinforce the "utility/developer" aesthetic.

- **Headlines:** Use tight letter-spacing and bold weights to feel impactful and grounded.
- **Labels:** Technical labels (like version numbers or hardware specs) should always use the `label-caps` style in JetBrains Mono.
- **Hierarchy:** Use color (dimming to 60% opacity) rather than just size to differentiate between primary and secondary body information.

## Layout & Spacing
This design system is optimized for a **Fixed Window Layout (1180x840)**. It utilizes a structured internal grid to manage information density without feeling cluttered.

- **Grid:** A 12-column grid system is used within the main content area.
- **Sticky Panels:** The primary navigation and "Global Deploy" action are housed in sticky sidebar or bottom panels to ensure they are always accessible.
- **Density:** High information density is encouraged through the use of compact padding (`sm` and `md`) to allow power users to see more data at once.
- **Responsiveness:** Since the window is fixed, layout changes focus on "expandable" sections rather than viewport reflow.

## Elevation & Depth
Depth is created through **Tonal Layering** and **Backdrop Blurs** rather than traditional drop shadows.

- **Level 0 (Base):** The darkest background color.
- **Level 1 (Panels):** Slightly lighter navy/charcoal with a 1px inner border (10% white opacity) to define edges.
- **Level 2 (Modals/Popovers):** Uses a glassmorphic effect with `backdrop-filter: blur(12px)` and a slightly more prominent Cyan or Purple border glow.
- **Interactive States:** Hovering over cards should increase the inner border brightness and add a subtle primary-colored outer glow (`box-shadow: 0 0 15px rgba(124, 58, 237, 0.2)`).

## Shapes
The shape language is "Precision-Soft." While the design is modern, it avoids overly circular forms to maintain a serious, technical tone.

- **Small Components:** Checkboxes and small badges use a 2px radius.
- **Standard Buttons/Inputs:** Use the `rounded` (0.25rem) setting for a crisp, professional look.
- **Large Cards/Panels:** Use `rounded-lg` (0.5rem) to slightly soften the structure of the main window frames.

## Components
- **Buttons:** Primary buttons use a solid Deep Purple fill with white text. Secondary buttons are outlined in Cyan with a subtle 5% Cyan background tint.
- **Modern Toggles:** Use a "pill" track but a square-ish thumb with a subtle glow when active.
- **Expandable Cards:** These are the primary container for settings. They feature a 1px border. When expanded, the header should highlight in a subtle Cyan tint.
- **Readiness Badges:** Small, high-contrast labels (using JetBrains Mono) that use Success Green for "Ready" and Warning Amber for "Pending."
- **Input Fields:** Darker than the panel background with a "bottom-only" focus highlight in Cyan.
- **Sticky Panels:** The "Footer" panel should be semi-transparent glassmorphic to allow content to scroll underneath it visually, while remaining functionally static.