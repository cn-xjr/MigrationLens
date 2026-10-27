# External validation resources

These are validation-only dependencies. No Python package, upstream schema,
validator implementation or upstream test is bundled in this repository's source
distribution. The library's MoonBit runtime dependencies are unchanged.

The official SARIF schema is downloaded and checksum-checked using the source
revision/edition recorded in [sarif-schema-lock.json](sarif-schema-lock.json).
It retains OASIS's terms: see the pinned
[repository license notice](https://github.com/oasis-tcs/sarif-spec/blob/a560296ca8c921f3bdb8d4a8db57ab83dae968a7/LICENSE.md).
The project's Apache-2.0 license does not relicense this external resource.

Python packages below were resolved in an isolated Python 3.12 environment.
Versions are pinned in requirements.txt; license labels were checked against
installed distribution metadata/license files and project release metadata.
Each package retains its own distributed notices and terms.

| Package/release source | License |
| --- | --- |
| [check-jsonschema 0.39.0](https://pypi.org/project/check-jsonschema/0.39.0/) | Apache-2.0 |
| [jsonschema 4.25.1](https://pypi.org/project/jsonschema/4.25.1/) | MIT |
| [attrs 26.1.0](https://pypi.org/project/attrs/26.1.0/) | MIT |
| [certifi 2026.10.23](https://pypi.org/project/certifi/2026.10.23/) | MPL-2.0 |
| [charset-normalizer 3.5.2](https://pypi.org/project/charset-normalizer/3.5.2/) | MIT |
| [click 8.5.0](https://pypi.org/project/click/8.5.0/) | BSD-3-Clause |
| [idna 3.20](https://pypi.org/project/idna/3.20/) | BSD-3-Clause |
| [jsonschema-specifications 2025.9.1](https://pypi.org/project/jsonschema-specifications/2025.9.1/) | MIT |
| [referencing 0.37.0](https://pypi.org/project/referencing/0.37.0/) | MIT |
| [regress 2026.9.1](https://pypi.org/project/regress/2026.9.1/) | MIT |
| [requests 2.34.2](https://pypi.org/project/requests/2.34.2/) | Apache-2.0 |
| [rfc3986-validator 0.1.1](https://pypi.org/project/rfc3986-validator/0.1.1/) | MIT |
| [rpds-py 2026.9.1](https://pypi.org/project/rpds-py/2026.9.1/) | MIT |
| [ruamel.yaml 0.19.1](https://pypi.org/project/ruamel.yaml/0.19.1/) | MIT |
| [typing_extensions 4.16.0](https://pypi.org/project/typing-extensions/4.16.0/) | PSF-2.0 |
| [urllib3 2.8.0](https://pypi.org/project/urllib3/2.8.0/) | MIT |

Python 3.12 is external tooling under its
[PSF license terms](https://docs.python.org/3.12/license.html); pip is MIT.
CI uses actions/setup-python (MIT). These runtimes/actions are not redistributed.
The GitHub profile and all negative cases are authored here under Apache-2.0,
using the official GitHub support documentation as a semantic reference. No
upstream validation logic or example payload is copied.
