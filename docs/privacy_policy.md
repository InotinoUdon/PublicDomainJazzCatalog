# Privacy Policy

**Effective date:** 2026-05-09  
**Last updated:** 2026-05-09

This Privacy Policy describes how **Public Domain Jazz** (the mobile application; the "App") handles information. The **data controller** is the developer identified as the seller/publisher on the app store listing where you obtained the App (for example Google Play or Apple App Store).

The App is **not** an official Library of Congress product. It displays metadata and plays audio from URLs described in the app’s catalog; third-party servers (including archival hosts) may process technical data when you use those features.

---

## 1. Scope

This policy applies to:

- The App as distributed through official app stores or sideload builds from the open-source project.
- In-app opening of **Privacy Policy** and **Terms of Use** URLs (see [Section 10](#10-where-this-policy-is-published)).
- Network use described below, including the **default catalog JSON** URL configured in the App build (overridable at build time via `CATALOG_REMOTE_URL` in the open-source project).

---

## 2. Information the App processes

The App is designed to operate with **minimal** collection of personal data.

### 2.1 What we do not ask for in the App

- No account registration.
- No name, email address, or phone number collected **through the App UI**.
- No precise location permission requested.
- No access to contacts, photos, calendar, or SMS.

### 2.2 Data on your device

The App may store **local** data only on your device, for example:

- **Cached catalog JSON** (e.g. after a successful download) to improve startup and offline fallback behaviour.
- **Playback-related state** (e.g. current queue, favorites in the current session as implemented).

This data remains on your device until you uninstall the App or clear app storage. It is not transmitted to the App developer as a separate “profile” by the App’s own analytics layer (see [Section 6](#6-analytics-and-advertising)).

### 2.3 Network activity (technical data)

When you use the App, your device sends **ordinary internet requests** that are technically required for functionality, including to:

| Purpose | Typical destination (examples) |
|--------|----------------------------------|
| Load the track catalog (`tracks.json` or equivalent) | HTTPS host configured for the build (e.g. GitHub Pages for this catalog site) |
| Stream or download audio | Hosts named in the catalog (e.g. Library of Congress infrastructure when listed) |
| Open source, rights, or legal pages | Hosts you choose when you tap in-app links (e.g. GitHub Pages for markdown policies, or loc.gov) |

Those servers—including networks between you and them—may process **standard technical information** (such as IP address, user agent, timestamps) according to **their** policies. The App does not embed third-party advertising or analytics SDKs in the current open-source configuration (see [Section 6](#6-analytics-and-advertising)).

---

## 3. Permissions (Android)

The App requests **INTERNET** access so it can fetch the catalog and stream audio. No other dangerous permissions are required for the described open-source behaviour.

---

## 4. Third-party services and links

The App may open **third-party websites** when you use features such as “source item”, “rights”, or legal links. Those sites have their own terms and privacy practices. The App publisher does not control third-party sites.

---

## 5. Children’s privacy

The App is not specifically directed to children. If your jurisdiction imposes additional requirements, the publisher may update this policy.

---

## 6. Analytics and advertising

The current open-source App **does not** integrate dedicated user analytics SDKs or advertising SDKs.

If that changes in a future release, this policy will be updated **before** broader distribution, and store listings and in-app links will be aligned.

---

## 7. International users

If you use the App outside the publisher’s country, your information may be processed in accordance with this policy and applicable law in those regions as part of normal internet routing and third-party hosting.

---

## 8. Your choices

- You can **stop** using the App at any time.
- You can **clear app data** or uninstall to remove local cache and state held on the device (subject to OS behaviour).

---

## 9. Changes to this policy

We may update this policy from time to time. The **Effective date** at the top will be revised when material changes are made. Continued use of the App after updates means you acknowledge the updated policy where required by law.

---

## 10. Where this policy is published

- **Public URL (GitHub Pages for the catalog; in-app default):**  
  `https://inotinoudon.github.io/PublicDomainJazzCatalog/privacy_policy.md`  
  This repository’s workflow copies `docs/privacy_policy.md` into the published site together with `tracks.json`.

- **This repository (catalog / Pages source):**  
  `docs/privacy_policy.md` in  
  [https://github.com/InotinoUdon/PublicDomainJazzCatalog](https://github.com/InotinoUdon/PublicDomainJazzCatalog)

- **Application repository (synchronized copy; keep wording aligned):**  
  `docs/privacy_policy.md` in  
  [https://github.com/InotinoUdon/PublicDomainJazzPlayer](https://github.com/InotinoUdon/PublicDomainJazzPlayer)

Store listings should reference the **same URL** you ship in the App build, so users and reviewers see consistent text.

---

## 11. Contact

- **Privacy inquiries:** use the **contact email or form shown on the app store listing** for this App (Google Play / Apple App Store). That channel is the primary way to reach the publisher for privacy-related questions.

- **Technical issues (mobile app):**  
  [https://github.com/InotinoUdon/PublicDomainJazzPlayer](https://github.com/InotinoUdon/PublicDomainJazzPlayer)  
  for bugs or documentation; it is **not** a substitute for legal or privacy notices required in your jurisdiction.

- **Catalog / `tracks.json` / GitHub Pages deployment:**  
  [https://github.com/InotinoUdon/PublicDomainJazzCatalog/issues](https://github.com/InotinoUdon/PublicDomainJazzCatalog/issues)

---

## 12. Play Console / App Store alignment

When you complete **Data safety** (Google Play) or **Privacy nutrition** (Apple) forms, answer them based on **this document** and the **actual** build you submit (including any `dart-define` overrides). If the form asks about data “collected” or “shared”, disclose categories that match **network and device behaviour** above; do not claim “no data” if your build or third-party endpoints still process technical server logs.
