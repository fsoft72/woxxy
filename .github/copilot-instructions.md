# Copilot Instructions

These are the instructions for GitHub Copilot to follow while generating code for this project:

- Follow the project's coding standards and conventions.
- If a functionality requires new components / views, always create components and screens in `lib/components` and `lib/screens`.
  **DO NOT ADD MULTIPLE COMPONENTS / SCREENS TO THE SAME FILE**
- Ensure all code is well-documented with comments.
- Keep functions and methods small. If needed, create some internal methods / functions to keep code readable.
- Write clean, readable, and maintainable code.
- Use meaningful variable and function names.
- Avoid using deprecated or outdated libraries and functions.
- Ensure compatibility with the project's existing dependencies and environment.
- Follow the project's folder structure and organization.
- Prioritize performance and efficiency in the code.
- Ensure all code passes linting and formatting checks.

- when possible, write one liners, for eg.
  ```javascript
  if ( a ) {
    return null
  }
  ```

  is best written in this way:

  ```javascript
  if ( a ) return;
  ```
