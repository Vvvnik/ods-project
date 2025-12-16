# License Information

This project uses a two-license model (different licenses for different parts of the project):

- **Code and scripts** are licensed under the **Apache License 2.0**.  
  See [LICENSE-CODE.md](./LICENSE-CODE.md) for details.

- **Documentation, templates, and text materials** are licensed under the **Creative Commons Attribution 4.0 International (CC-BY 4.0)**.  
  See [LICENSE-DOCS.md](./LICENSE-DOCS.md) for details.

- **Third-party software licenses** are listed in [NOTICE.adoc](./NOTICE.adoc).

Commercial support and additional extensions (if any) are provided under separate terms and do not limit the Apache-2.0 / CC BY 4.0 licenses for this repository.

## Demo Data Notice

The demo data included in this project (such as the toys service API and database schemas) is provided **solely for documentation and demonstration purposes**. This demo data:

- Is fictional and created for example purposes only
- Does not represent real products, services, or business data
- Is intended to showcase ODS documentation capabilities
- Should not be used in production environments

## LLM Components Notice

This project includes LLM (Large Language Model) integration for automatic translations:

- **Ollama** is used under MIT License for local LLM server
- **LLM Models** are used under various licenses:
  - **gpt-oss:20b** - Apache License 2.0
  - **Gemma3 4B** - Gemma Terms of Use (Google)
  - **Gemma** - Gemma Terms of Use (Google)
  - **Mistral 7B** - Apache License 2.0
  - **Qwen2.5** - Tongyi Qianwen License (Alibaba)
- **LLM functionality** is optional and requires local installation
- **Translations** are generated locally and not sent to external services
- **Dictionary** contains pre-translated terms to reduce LLM usage
  - **Fastest model**: `gemma3:4b` for optimal speed and quality
  - **Recommended model**: `gemma:latest` for best balance of quality and speed

By contributing to this project, you agree that your contributions will be distributed under these licenses.
