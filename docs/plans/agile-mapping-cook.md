# Fix: Fragment navigation (#heading links) doesn't scroll to heading

## Context

When clicking a markdown link with a fragment like `[Path-prefix routing](../security-crypto.md#router-enforcement)`, the file opens but doesn't scroll to the heading. Three independent bugs cause this.

---

## Root Causes

### Bug 1: URL fragment poisons `currentURL` and `representedURL`

`load(from:)` stores the full URL including `#fragment` in `currentURL` (line 485). This propagates to `window.representedURL` (line 1686). Subsequent comparisons against fragment-less URLs fail unpredictably.

### Bug 2: Existing-tab detection fails for fragment URLs

`openFileLink()` compares `url.standardizedFileURL` (with fragment) against `window.representedURL.standardizedFileURL` (without fragment). URL equality includes fragments, so the match always fails. The code never finds the existing tab.

### Bug 3: Existing-tab path scrolls before page loads

Even if the existing-tab match worked, `scrollToFragment()` runs immediately after `load()` — but `load()` triggers async `loadHTMLString()`. By the time the page finishes loading, the scroll has already executed against the old DOM and been discarded. `pendingFragment` is never set on the target model, so `didFinish` can't scroll either.

---

## Changes

### 1. Strip fragment from `currentURL` in `load(from:)`

**File:** [MarkdownDocumentModel.swift](QuickMDApp/MarkdownDocumentModel.swift) (line ~485)

Before setting `currentURL`, strip the fragment. Fragments are for navigation, not file identity.

### 2. Strip fragment in `openFileLink()` for window matching

**File:** [ContentView.swift](QuickMDApp/ContentView.swift) (`openFileLink()` ~line 440)

Extract fragment from URL before comparison. Use a fragment-less URL for `standardizedFileURL` matching. Set `tabModel.pendingFragment = fragment` before calling `tabModel.load()`. Remove the premature `scrollToFragment()` call — `didFinish` handles it via `pendingFragment`.

### 3. Reload from disk + set pendingFragment in `switchToWindowWithURL()`

**File:** [MarkdownDocumentModel.swift](QuickMDApp/MarkdownDocumentModel.swift) (`switchToWindowWithURL()` ~line 409)

After switching to the existing window, find the model via `ZoomableWebView.commentCoordinator.model` and call `load(from:)` to ensure fresh content. Add a `pendingFragment` parameter so callers (`goBack`/`goForward`) can pass fragments too.

---

## Files modified

| File | Change |
|------|--------|
| [MarkdownDocumentModel.swift](QuickMDApp/MarkdownDocumentModel.swift) | Strip fragment from `currentURL`, reload model in `switchToWindowWithURL()`, add `reloadModelInWindow()` helper |
| [ContentView.swift](QuickMDApp/ContentView.swift) | Strip fragment for window matching in `openFileLink()`, set `pendingFragment` instead of immediate scroll |

---

## Verification

1. **Fragment link navigation:**
   - Click a link like `[Heading](other-file.md#some-heading)`
   - Verify: file opens AND scrolls to the heading
   - Test with file already open in another tab
   - Test with new tab and same-tab navigation

2. **Plain file links still work:**
   - Click a link without fragment like `[File](other-file.md)`
   - Verify: file opens normally at top

3. **Back/forward with fragments:**
   - Navigate to `file.md#section`, then back, then forward
   - Verify: scroll position is correct each time

4. **Run tests:**
   ```bash
   xcodebuild test -scheme QuickMDApp -only-testing QuickMDTests \
     CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
     CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES SWIFT_VERSION=5.0 \
     SWIFT_ENABLE_EXPLICIT_MODULES=NO ENABLE_TESTABILITY=YES
   ```
