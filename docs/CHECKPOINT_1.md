# Checkpoint 1: CloseCode — Licensed Software Application Immune to Software and Microarchitectural Attacks <!-- omit from toc -->

> [!NOTE]
> Renamed the project type from _Software License Server Immune to Software and Microarchitectural Attacks_ to _Licensed Software Application Immune to Software and Microarchitectural Attacks_ to avoid generating confusion due to the ubiquity of web client-server applications since CloseCode is purely an application.

- **Team:** Null and Void
  - Pablo Ordorica Wiener ([@pablordoricaw](www.github.com/pablordoricaw))
- **Semester:** Spring 2026
- **Instructor:** Simha Sethumadhavan
- **TA:** Ryan Piersma

## Table of Contents <!-- omit from toc -->

- [Introduction](#introduction)
- [System Architecture](#system-architecture)
- [Threat Model](#threat-model)
- [Project Plan](#project-plan)
- [Artifact List](#artifact-list)
- [References](#references)

## Introduction


## System Architecture

> [!NOTE]
> I used the C4 model to model the architecture for CloseCode and generate the diagrams in this section. The C4 model is a simple architectural modeling technique developed by Simon Brown that has 4 hierarchical levels of abstractions to create a map of the design. Each level of abstraction "zooms-in" or "zooms-out" the level of detail. These abstractions are:
>
> 1. Context: Highest level of abstraction composed of software systems that deliver value to users independently.
> 2. Container: (Not a Docker container) A container represents a piece of software in a software system that needs to be running in order for the overall system to work. Think of an application or a data store that is independently deployable.
> 3. Component: A component is a grouping of related functionality encapsulated behind a well-defined interface.
> 4. Code: Classes, functions, enums, etc.
>
> The architecture model is defined as code in [docs/architecture/workspace.dsl](./architecture/workspace.dsl) using the DSL of the [Structurizr](https://docs.structurizr.com/) and diagrams were generated using the [Structurizr Playground](https://playground.structurizr.com/)

I modeled the architecture of CloseCode down to the Component level of the C4 model for which the next sections have the corresponding diagrams.

### Level: Context Diagram

First off is the Context level diagram.

<img src="./figs/c4-context-view.png" width="1200">

### Level: Container Diagram

<img src="./figs/c4-container-view.png" width="1200">

### Level: Component Diagrams

#### ClodeCode App Component Diagram

<img src="./figs/c4-component-view-closecode-app.png" width="1200">

## Threat Model


## Project Plan


## Artifact List


## References

1. Simon Brown. *The C4 model for visualising software architecture.* https://c4model.com/
2. Simon Brown. *Structurizr documentation.* https://docs.structurizr.com/
3. Structurizr Playground. https://playground.structurizr.com/
4. Anthropic. *Claude Code overview / documentation.* https://docs.anthropic.com/
5. Open Code project repository. https://github.com/sst/opencode
6. Microsoft. *The STRIDE Threat Model.* https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats
7. NIST. *Secure Hash Standard (SHS), FIPS 180-4.* https://csrc.nist.gov/pubs/fips/180-4/upd1/final
8. NIST. *Recommendation for Keyed-Hash Message Authentication Codes (HMAC), FIPS 198-1.* https://csrc.nist.gov/pubs/fips/198-1/final
9. NIST. *Digital Signature Standard (DSS), FIPS 186-5.* https://csrc.nist.gov/pubs/fips/186-5/final
10. Apple Developer Documentation. *App Attest.* https://developer.apple.com/documentation/devicecheck/establishing_your_app_s_integrity
11. Apple Developer Documentation. *Protecting keys with the Secure Enclave.* https://developer.apple.com/documentation/security/protecting_keys_with_the_secure_enclave
12. Intel. *Intel Software Guard Extensions (Intel SGX).* https://www.intel.com/content/www/us/en/developer/tools/software-guard-extensions/overview.html
13. Martin Fowler. *Architecture Decision Records.* https://martinfowler.com/articles/adr.html
