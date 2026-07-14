# 0014 – Deneb Vega-Lite Regional Map

**Status**: Accepted  
**Date**: 2026-07-14  

## Context

The report's regional analysis page (canonical page list: [methodology.md](../methodology.md)) presents revenue across nine European markets and their key first-level administrative regions. The map anchoring that page must satisfy three constraints at once. First, the report is published as a public publish-to-web embed, where only certified custom visuals render – and certification prohibits external service access, so any visual that fetches tiles or geometry at render time is excluded inside the Service iframe sandbox. Second, the map must render identically everywhere it is opened – Desktop, the Service, the public embed – with no dependence on network availability or on a map provider's styling decisions. Third, the map must follow the report's palette and typography exactly; a provider-styled basemap that cannot be recolored breaks the report's visual system.

## Decision

Build the map as a choropleth in the certified Deneb custom visual, specified in Vega-Lite, with the entire basemap embedded in the spec. The basemap is a single TopoJSON object of 189 features – 1 land silhouette, 67 surrounding country outlines, 9 market countries, and 112 first-level administrative regions – with every feature tagged by a layer property. The spec derives its visual layers from that one object through per-layer property filters. Nothing in the spec references an external URL: geometry, projection, color scale, and labels are fully self-contained.

The basemap is derived from Natural Earth 10m cultural vectors, filtered to the market scope, simplified, and merged into the single tagged object by a deterministic, version-pinned mapshaper build.

## Consequences

- The spec structure is constrained by how Vega-Lite compiles data references: each combination of dataset name and `format.feature` becomes its own Vega data source, and the generated source name is not disambiguated by format. Multiple layers referencing one named dataset with different `format.feature` settings therefore collide at runtime with "Duplicate data set name". The single tagged object with per-layer filter transforms is the required pattern – discovered by hitting that collision – and a second `format.feature` reference against the shared basemap must not be reintroduced.
- Rendering is self-contained, but regeneration is not. The basemap build scripts live outside the tracked repository and depend on locally held Natural Earth source data and pinned tooling. The build is deterministic – repeated runs produce byte-identical output – but reproducing the basemap requires that local environment.
- The basemap derives from [Natural Earth](https://www.naturalearthdata.com), a public-domain dataset; no attribution is required, and it is given here.
- The geometry payload (roughly 370 KB of TopoJSON) lives inside the report definition, so any basemap change surfaces as one large diff in the visual definition. That is the accepted cost of self-containment.
- The report carries Deneb as a registered custom-visual dependency; were the visual withdrawn from AppSource, the map would need re-implementation.
- The map is code end to end – spec, basemap, and build are all reviewable text artifacts – consistent with the operating standard in [ADR 0001](0001-end-to-end-engineering-as-operating-standard.md).

## Alternatives Considered

- **Tile-based maps (Bing, Mapbox, OpenStreetMap tiles)** – rejected. Tile fetches are external calls: they fail certification or require an uncertified visual, and uncertified visuals do not render in a publish-to-web embed.
- **Azure Maps** – rejected. The current native mapping visual, but unsupported in publish-to-web at the time of evaluation (June 2026).
- **Filled Map (Bing)** – rejected. Rendered in publish-to-web at the time of evaluation, but scheduled for deprecation, and its provider-locked styling cannot follow the report palette.
- **Shape Map** – rejected. The one native visual that accepts a custom TopoJSON, but in preview at the time of evaluation, with limited styling control.
