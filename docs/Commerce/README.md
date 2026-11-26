# Liya consumable coin packs

The wallet displays nine consumable coin packs with US reference prices. Selecting a pack starts a StoreKit 1 product request for that identifier. Liya shows the price and currency returned for the customer's storefront before offering the Apple purchase button. `COIN_PRODUCTS.json` lists the product identifiers, quantities and target US prices for App Store Connect. The Bundle ID is `com.liyalumora.auroramuse`.

The app observes Apple's payment queue from launch. When Apple reports a completed purchase for a known pack, Liya saves the credit and transaction ID together before finishing the transaction. An interrupted delivery can be processed again, including after relaunch. Apple handles billing and refunds. StoreKit 1's payment queue does not supply a complete refund history for delivered consumables. Finished consumables have no cross-device restore from this wallet.

The device wallet also stores the 600-coin welcome gift and the appearance unlocks. Mood Prism costs 120 coins and changes the Mood Diary palette. Profile Glow costs 180 and changes the profile accents. Each unlock can be reapplied without another charge. Between days includes Daybreak postcard paper. Tideglass paper costs 90 coins once on this device and can be reused on future postcards. Exporting a postcard carries no charge.

Checkout and the coin ledger run independently of the Liya backend. Existing wallets retain their transaction IDs, welcome-gift status and unlocked styles. StoreKit 1 uses the installed receipt location to select the local ledger partition. A receipt filename alone cannot distinguish every Xcode test setup from the sandbox. If an earlier wallet has ambiguous purchase history, the app preserves its file and lets the user refresh the receipt through Apple. A new wallet can display its welcome balance before the first receipt is available.

App Store Connect product availability, real StoreKit purchase and recovery, plus application build and device behavior, have not been verified.
