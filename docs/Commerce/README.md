# Liya consumable coin packs

StoreKit 2 loads Liya's configured consumables and presents Apple's purchase sheet. The wallet uses Apple's localized storefront prices. `COIN_PRODUCTS.json` records the nine identifiers, amounts and target US prices for App Store Connect. The Bundle ID is `com.liyalumora.auroramuse`.

The device wallet uses a locally generated token for new purchases. It grants coins only for verified StoreKit transactions that match the wallet and a known consumable. The local ledger records each transaction once per StoreKit environment, with production, sandbox and Xcode balances kept separate. The app writes the credit and transaction ID together before calling `finish()`. It checks unfinished transactions in the foreground and handles transaction updates while running, including Apple revocations. The wallet's Check purchases action retries delivery for the same wallet. Finished consumables have no cross-device restore from this wallet.

The device wallet also stores the 600-coin welcome gift and the appearance unlocks. Mood Prism costs 120 coins and changes the Mood Diary palette. Profile Glow costs 180 and changes the profile accents. Each unlock can be reapplied without another charge. Between days includes Daybreak postcard paper. Tideglass paper costs 90 coins once on this device and can be reused on future postcards. Exporting a postcard carries no charge.

The app's checkout and ledger require no Liya server. An aggregate read of the previous Supabase ledger found two welcome credits and zero Apple purchase records on 24 November 2026. No paid balance was available to import. A prior unfinished transaction with a different wallet token remains uncredited and unfinished in the new app. The old server tables retain their historical records.

App Store Connect product availability, real StoreKit purchase and recovery, plus application build and device behavior, have not been verified.
