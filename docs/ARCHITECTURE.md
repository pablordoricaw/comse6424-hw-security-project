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

<img src="../figs/c4-context-view.png" width="1200">

### Level: Container Diagram

<img src="../figs/c4-container-view.png" width="1200">

### Level: Component Diagrams

#### ClodeCode App Component Diagram

<img src="../figs/c4-component-view-closecode-app.png" width="1200">

## Trust Boundary Summary

| Component | Trust Level | Notes |
| :--- | :--- | :--- |

### Trust Boundary Notes
