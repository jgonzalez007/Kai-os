# Kai OS Licensing

## Code: MIT
All source code in this repository is licensed under the MIT License (see LICENSE).

## Documentation: CC-BY-4.0
All documentation, including this file, README, and architecture docs, is licensed under Creative Commons Attribution 4.0.

## Trademark
"Kai OS" and the Kai logo are trademarks of Kai OS Labs. Permission required for commercial use of the name/logo.

## Commercial Licensing
For commercial deployments of Kai OS beyond individual use, contact: licensing@kai-os.ai

## Origin and acknowledgements

Kai OS started as an idea to rebuild what [Sentient OS](https://github.com/Sentient-OS-Labs/sentient-os) does for a Mac notch (a personal AI that lives there). Sentient OS is licensed under the AGPL-3.0. Kai OS is a separate codebase under the MIT License, and this is how that was checked:

- Kai's history begins with its own scaffold, written for Kai. The notch window, the panels, Night Shift, the knowledge base, the Slack connector, Sidekick, Double Tap, the Desk features and the new look are written for Kai.
- On 2026-11-08 every Swift file in Kai was compared line by line with every Swift file in Sentient OS (`scripts/check-overlap.py`). No file shares 25 or more substantial lines with Sentient. The most any file shares is 13 lines, and those are generic framework calls (standard panel setup, SwiftUI modifiers, common type names), not logic. Run `scripts/check-overlap.py <path to the other repository>` to repeat it.
- Ideas and behavior, not code, were taken from Sentient OS: the fixed-canvas notch that ignores the mouse away from the shape, the hover swell, the open-edge glow, and the layout of Preferences. Ideas and interface layouts are not covered by a software license. Sentient's own notes credit the DynamicNotch project for the notch geometry; Kai's silhouette uses the same well-known construction.
- Names, logos and artwork of Sentient OS are not used.

This is an engineering check, not legal advice. If Kai OS is sold or offered to companies, have a lawyer confirm the choice of MIT.

## Contributing
By contributing code, you agree to license it under the MIT License.
