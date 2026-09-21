---
fileVersion: 1.0.0

---

# Repository layout

- `.github/workflows` contains the reusable GitHub Actions workflows. The `validate` workflow performs verification, `release-library` is a release workflow for NuGet library project whereas `release-executable` is used for for self-contained executable projects.
- The release workflows also run the same validate steps as the `validate` workflow.
- `.github/actions` contains the reusable composite actions used as building blocks by the workflows. Actions cover focused tasks such as checking versions, setting up .NET, building solutions, executing tests and handling artifacts.
- The root `README.md` file document how consuming repositories call the reusable workflows and how the workflows are composed.
- `tests` contains tests and fixtures for scripts used by the actions.

___

# Workflows and actions

- Workflows provide the higher-level orchestration for verification and CI/CD stages. They consume reusable actions through versioned `uses` references.
- Actions perform focused operations and expose inputs and outputs. A workflow passes values such as paths, configuration, tokens, and feature switches to actions through `with` and `secrets`.
- Implement workflow and action logic with PowerShell. PowerShell should be used consistently on all supported runners instead of Linux Bash.
- Prefer separate, reusable PowerShell script files that are called by workflows or actions instead of embedding scripts inline. This keeps the implementation easier to test with Pester.
- Keep the workflow and action contracts compatible. When an action changes its inputs, outputs, behavior, or required permissions, review the workflows that consume it.

___

# Changelogs

- Each reusable workflow has a corresponding changelog in `.github/workflows`.
- Each reusable action has its own changelog beside its `action.yml` in `.github/actions/<action-name>`.
- Read the relevant changelogs before changing workflow or action versions. They record contract changes, requirements, and updates to dependencies used by consumers.
- Adhere to [**Versioning**](./instructions/user.instructions.md#Environment) for versioning conventions.

___

# Tests

- PowerShell scripts are tested with the [Pester](https://pester.dev/) framework.