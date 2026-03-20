# Refactor Code

## Overview

Refactor the selected code to improve its quality while maintaining the same functionality, providing the refactored code with explanations of the improvements made.

**CRITICAL**: DO NOT WRITE BACKWARDS COMPATIBLE CODE!!! IF I REMOVE SOMETHING DO NOT ADD IT BACK AGAIN
IF TESTS ARE WRITTEN WITH THE OLD CODE UPDATE THEM TO THE NEW CODE. TESTS ARE NOT BACKWARD COMPATIBLE AND MUST NOT FORCE BACKWARD COMPATIBLE CODE. FOLLOW THIS RULE ALL THE TIME.

## Steps
0. **Follow Rules**
    - Follow master rule index @.cursor/rules/rules-index.mdc
    - Follow the code quality and complexity rule @.cursor/rules/code-quality.mdc

1. **Code Quality Improvements**
    - Extract reusable functions or components
    - Eliminate code duplication
    - Improve variable and function naming
    - Simplify complex logic and reduce nesting
    - think hard on where you can simplify code, without loosing functionality and features
2. **Performance Optimizations**
    - Identify and fix performance bottlenecks
    - Optimize algorithms and data structures
    - Reduce unnecessary computations
    - Improve memory usage
3. **Tests**
    - Write new tests, or adapt old tests, for the new code you generated during refactor
    - All tests must pass

3. **Maintainability**
    - Make the code more readable and self-documenting
    - Add appropriate comments where needed
    - Follow SOLID principles and design patterns
    - Improve error handling and edge case coverage
    - No backwards compatigility
    - No fallbacks to old code. Error conditions must raise exceptions
    - No db migrations
    - Get quality metrics on all the files modified by the refactoring and follow the @.cursor/rules/code-quality.mdc rule. All code must have A (preffered) or B (minimum) grades, anything else must be refactored


## Refactor Code Checklist

- [ ] Extracted reusable functions or components
- [ ] Eliminated code duplication
- [ ] Improved variable and function naming
- [ ] Simplified complex logic and reduced nesting
- [ ] Identified and fixed performance bottlenecks
- [ ] Optimized algorithms and data structures
- [ ] Made code more readable and self-documenting
- [ ] Followed SOLID principles and design patterns and rules
- [ ] Improved error handling and edge case coverage
- [ ] CRITICAL: maintainability index should get A Grade prefered, B grade minimum, anything else is a fail on this criteria and you must refactor
- [ ] All tests related to the refactored code must pass
