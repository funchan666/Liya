# Liya consumable coin packs

## App Store Connect entries

Use the existing Liya app record with Bundle ID `com.liyalumora.auroramuse`. Choose **Consumable** for all nine products and **English (U.S.)** for these display names and descriptions. Each display name can also serve as the internal reference name. The last column gives the intended US storefront price.

| Display name | Description | Product ID | US price |
| --- | --- | --- | ---: |
| 450 Liya Coins | Adds 450 coins to your Liya wallet. | `ceyarlaxiuojqsbi` | $0.99 |
| 950 Liya Coins | Adds 950 coins to your Liya wallet. | `gxaojqvpvmykrgif` | $1.99 |
| 1500 Liya Coins | Adds 1500 coins to your Liya wallet. | `hzlqemvjatucwprd` | $2.99 |
| 2700 Liya Coins | Adds 2700 coins to your Liya wallet. | `hqahzvljpcaltfnm` | $4.99 |
| 5800 Liya Coins | Adds 5800 coins to your Liya wallet. | `npdkdztghlqpfxnr` | $9.99 |
| 9000 Liya Coins | Adds 9000 coins to your Liya wallet. | `qwnbrlxesdvyampt` | $14.99 |
| 12500 Liya Coins | Adds 12500 coins to your Liya wallet. | `czyghtwgjcswnuvl` | $19.99 |
| 34000 Liya Coins | Adds 34000 coins to your Liya wallet. | `jemidcjpjteygrfy` | $49.99 |
| 72000 Liya Coins | Adds 72000 coins to your Liya wallet. | `qmubwwcjusfbmlpw` | $99.99 |

## Review and checkout

Sign in, open **Profile**, tap the coin balance to open **My wallet**, and select a pack. The wallet displays US reference prices before selection. It requests the selected product from StoreKit 1 and shows Apple's localized price before **Buy with Apple** opens the payment sheet.

For the initial release, configure the nine products in App Store Connect with their exact identifiers, prices, storefront availability, localizations and review screenshots. Include the packs offered at launch in the submission with the new app version. Apple reviews purchases in its sandbox using the App Store Connect catalog. [Apple product setup](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases) · [Submitting the first consumable](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase) · [Apple review environment](https://developer.apple.com/library/archive/technotes/tn2413/index.html)

The Xcode project declares version 1.0. Supply an unused build number for that version at archive time, since the checked-in project leaves `CURRENT_PROJECT_VERSION` unset. [Uploading builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)

## Coin delivery and spending

The app observes Apple's payment queue from launch. When Apple reports a completed purchase for a known pack, Liya saves the credit and transaction ID together before finishing the transaction. An interrupted delivery can be processed again, including after relaunch. Apple handles billing and refunds. StoreKit 1's payment queue does not supply a complete refund history for delivered consumables. Finished consumables have no cross-device restore from this wallet.

The device wallet also stores the 600-coin welcome gift and the appearance unlocks. Mood Prism costs 120 coins and changes the Mood Diary palette. Profile Glow costs 180 and changes the profile accents. Between days includes Daybreak postcard paper, with Tideglass available for 90 coins. Each unlock is reusable. These three items are all the current spending options and cost 390 coins in total. A new wallet can unlock all three with its welcome gift and retain 210 coins. Exporting a postcard carries no charge.

Checkout and the coin ledger run independently of the Liya backend. Existing wallets retain their transaction IDs, welcome-gift status and unlocked styles. StoreKit 1 uses the installed receipt location to select the local ledger partition. A receipt filename alone cannot distinguish every Xcode test setup from the sandbox. If an earlier wallet has ambiguous purchase history, the app preserves its file and lets the user refresh the receipt through Apple. A new wallet can display its welcome balance before the first receipt is available.

App Store Connect product availability, real StoreKit purchase and recovery, plus application build and device behavior, have not been verified.
