# KOReader-notities voor Lingering UI

Gelezen in KOReader **v2026.07.1** (tag bestaat; kloon in `~/Projects/koreader-src`,
alleen om te lezen). Dit document is de kaart voor reparaties na een KOReader-update:
elke haak hieronder hoort in `koreader/` terug te komen.

Paden zijn relatief aan de KOReader-bron.

## Architectuur en bestanden

Lagen (afhankelijkheden alleen naar beneden; `tools/check.sh` controleert de regels):

| Laag | Inhoud | Mag gebruiken |
|---|---|---|
| `ui/` | schermen met KOReader-widgets | `app/`, `koreader/` (weergave-data), `domain/`, widgets |
| `app/` | use cases en beleid | `domain/`, `koreader/`, algemene KOReader-bibliotheken (logger, UIManager, LuaSettings, DataStorage, util, lfs, sha2, time) — geen internals van plugins/widgets |
| `koreader/` | **anti-corruption layer**: het enige dat KOReader-internals kent; geeft gewone data terug | alles van KOReader, `domain/` |
| `domain/` | business rules, pure Lua | alleen `domain/` |

`tools/check_refs.lua` dwingt dit af: `domain/` laadt alleen `domain/`; `app/` alleen
algemene bibliotheken; `ui/`, `app/` en `main.lua` gebruiken geen `G_reader_settings`,
`NetworkMgr`, `getPowerDevice` of `Device:has…/is…/get…` (wel `Device.screen` voor maten).

| Bestand | Inhoud |
|---|---|
| `_meta.lua`, `main.lua` | plugin (moeten bovenin); `main.lua`: module-lader voor `lingering.<map>.<naam>`, bedraden, menu-item |
| `config.lua` | vaste adressen |
| `LICENSE` | AGPL-3.0 (zoals KOReader); gaat mee naar de Kobo. luaunit (alleen tests): BSD, `tests/vendor/LICENSE-luaunit.txt` |
| `domain/sync_rules.lua` | "verder wint, nooit blind wegschrijven" |
| `domain/catalog.lua` | OPDS-item → map/boek, beste download-link (EPUB eerst), bestandsnaam |
| `domain/reading_time.lua` | gelezen/resterende tijd uit statistieken |
| `domain/layout.lua` | tikzone-geometrie, rasterrijen vanaf y = 0 |
| `app/sync_service.lua` | reconcile, sync-knop, beleid voor automatische momenten |
| `app/account_service.lua` | inloggen: controleren en opslaan |
| `app/library_service.lua` | Mijn boeken: cache, synchroniseren, downloaden, omslagen |
| `app/session.lua` | eigen instellingen (`lingering.lua`), sessiestatus |
| `koreader/try.lua` | pcall-hulp voor elke haak |
| `koreader/reader.lua` | tikzones + overrides, menu blokkeren, bladeren, inhoudsopgave |
| `koreader/navigation.lua` | boek openen/sluiten, volledig menu |
| `koreader/kosync.lua` | sessie (ophalen/wegschrijven/springen), haken → beleid, binary, account |
| `koreader/opds.lua` | inloggegevens, client, ophalen, downloaden, omslag, account |
| `koreader/network.lua` | wifi, online, netwerkscherm |
| `koreader/device.lua` | licht, helderheid, batterij |
| `koreader/books.lua` | huidig boek, omslag, statistieken (ruw), thuismap |
| `koreader/global_settings.lua` | afgedwongen KOReader-instellingen, back-ups |
| `koreader/dialogs.lua` | kaal invoervenster |
| `koreader/update.lua` | zelf-update: tags (GitHub-API), zip van een tag (codeload), uitpakken (`ffi/archiver`), controleren, verwisselen, opruimen, herstarten |
| `app/update_service.lua` | zelf-update: zoeken, installeren (alleen tags), restanten opruimen bij de volgende start |
| `domain/release.lua` | versies lezen/vergelijken, nieuwste tag, welke paden bij de plugin horen |
| `ui/*.lua` | homescreen (blokken met stapels omslagen voor de mappen in `config.collections`; tik opent die map in Mijn boeken), Mijn boeken, Instellingen, Over Lingering (met update-knop, `ui/update_flow.lua`), inlogscherm, leesscherm, actiebalk, `book_opener.lua` (openen of downloaden-en-openen), gedeelde widgets |
| `icons/` | iconen uit [Material Symbols](https://fonts.google.com/icons) Outlined, gewicht 300 (`@material-symbols/svg-300` v0.48.0, Apache-2.0, `icons/LICENSE-material-symbols.txt`), ongewijzigd (uitzondering: `more_vert.svg` uit `svg-700`, dikgedrukt); `sync-<hoek>.svg` zijn kopieën, tegen de klok in gedraaid (zoals de pijlen van `sync`), voor de sync-animatie. Gekozen omdat het als enige open set alle iconen heeft (ook `mobile_rotate`/`mobile_rotate_lock`) |
| `tests/` | unit tests (luaunit, `tests/vendor/`), nep-adapters (`fakes.lua`), rooktest (`smoke.lua`) |
| `tools/check.sh` | syntax, verwijzingen (bestaat elke aangeroepen functie?), laagregels |
| `tools/test.sh` | unit tests met de LuaJIT uit de Flatpak (zonder KOReader) |
| `tools/deploy.sh` | plugin op een aangesloten Kobo zetten (zonder ontwikkelbestanden), na controles en tests |
| `tools/release.sh` | nieuwe versie: versie in `_meta.lua`, controles, commit, tag `v<versie>`, optioneel `--push` |
| `tools/smoke.sh` | rooktest in de emulator (`LINGERING_TEST=fm|reader`), met schermafdrukken: homescreen, Mijn boeken, map, Instellingen, Account, inloggen (goed én fout wachtwoord), downloaden naar een tijdelijk pad, omslag zonder cache; in het boek actiebalk, inhoudsopgave, sync, springen, wegschrijven (**schrijft echte voortgang naar het account**), sluiten |

Na een KOReader-update: `tools/check.sh`, `tools/test.sh`, `tools/smoke.sh`; bij fouten eerst
`koreader/` (en de tabel "Haken" hieronder), daarna `ui/`.

## Zelf-update

Instellingen → Update: wifi aan → tags van `config.update_repo` via
`https://api.github.com/repos/<repo>/tags` → hoogste `vX.Y.Z` (`domain/release.lua`) →
nieuwer dan `version` in `_meta.lua`? → vragen → zip van de tag
(`https://codeload.github.com/<repo>/zip/refs/tags/<tag>`) naar `<pluginmap>.update.zip` →
uitpakken naar `<pluginmap>.new` (alleen `_meta.lua`, `main.lua`, `config.lua`, `LICENSE`, `app/`,
`domain/`, `koreader/`, `ui/`, `icons/`; libarchive weigert `..`-paden) → alle Lua-bestanden
`loadfile` → `<pluginmap>` → `<pluginmap>.bak`, `.new` → `<pluginmap>` → zip weg →
`UIManager:askForRestart`. Bij de eerste start van de nieuwe versie ruimt `main.lua` `.bak`,
`.new` en de zip op (tot dan is `.bak` de weg terug). Is de pluginmap een symlink
(ontwikkelopstelling), dan wordt niet bijgewerkt. Alleen tags, geen branches.

## Testen in de emulator

- Schermformaten: `EMULATE_READER_W`, `EMULATE_READER_H`, `EMULATE_READER_DPI` als
  `flatpak run --env=…`. Getest: 1072×1448 @ 300 dpi (Clara) en 758×1024 @ 212 dpi (Nia).
- `EMULATE_BW_SCREEN=1` laat KOReader v2026.07.1 in de Flatpak meteen afsluiten (los van
  Lingering); grijstinten daarom achteraf met ImageMagick bekeken.
- In de emulator (SDL) zijn `hasWifiToggle` en `hasFrontlight` onwaar: wifi- en
  lichtknoppen staan grijs. Wifi, licht, slaapstand en offline-gedrag alleen op de Kobo te testen.

## Pluginladen

`frontend/pluginloader.lua`
- `PluginLoader:_discover()`: elke map `*.koplugin` in `plugins/` en in
  `extra_plugin_paths` (standaard `<datadir>/plugins/`). De pluginnaam is de
  mapnaam zonder `.koplugin`, dus `lingering`.
- `PluginLoader:_load()`: `dofile(main.lua)`, daarna worden de velden uit
  `_meta.lua` erin gekopieerd. **Een veld `name` in `_meta.lua` wordt genegeerd en geeft
  een waarschuwing** ("name in _meta.lua, is deprecated"). Daarom staat `name` alleen
  in `main.lua`.
- Alle `on*`-functies van de plugin worden in `HandlerSandbox` gewikkeld (pcall).
  Een fout in een event-handler crasht KOReader dus niet, maar `init()` valt daar niet
  onder: `createPluginInstance` doet wel een `pcall(plugin.new)`, dus een fout in
  `init` laat alleen het laden van de plugin mislukken.
- De pluginmap staat tijdens het laden vooraan in `package.path`, daarna achteraan. Na
  het laden zijn modules van andere plugins te `require`n (`require("opdsbrowser")`,
  `require("KOSyncClient")`).
- Instanties: één per `FileManager` (`filemanager.lua`, `FileManager:init`, alleen als
  `is_doc_only` niet waar is) en één per `ReaderUI` (`readerui.lua`, `ReaderUI:init`).
  Bij elke wissel lezer ↔ bestandsbeheer wordt de oude instantie weggegooid
  (`PluginLoader:finalize`) en een nieuwe gemaakt. `self.ui.document` bestaat alleen in
  de lezer.
- Uitschakelen via `plugins_disabled[naam]` in `settings.reader.lua`
  (menu Tools → More tools → Plugin management).

## Opstarten en schermwissels

- `reader.lua` (r. ~255): `start_with` (standaard `"filemanager"`). Bij `"last"` opent
  KOReader direct het laatste boek, en dan ziet de gebruiker het homescreen pas na het
  sluiten. Op deze installatie staat `start_with` niet ingesteld (= filemanager).
- `ReaderUI:showReader(file)` (`frontend/apps/reader/readerui.lua`): de enige
  veilige manier om een boek te openen. Stuurt `ShowingReader` en sluit daarmee de
  FileManager.
- `ReaderUI:onHome()`: `onClose()` gevolgd door `showFileManager(file)`. Dat is de nette
  weg om een boek te sluiten en terug te gaan.
- `ReaderUI:onClose()` stuurt `CloseDocument` **vóór** het document sluit en vóór de
  FileManager terugkomt. Kosync pusht in die handler.
- `ReaderUI:showFileManager()`: maakt een nieuwe FileManager (`FileManager:showFiles`)
  als er geen instantie is, en dan draait onze `init` in FM-context opnieuw. Dat is het
  moment om het homescreen te tonen.

## Gebeurtenissen naar widgets (`frontend/ui/uimanager.lua`, `UIManager:sendEvent`)

Invoer gaat naar het **bovenste** venster. Wordt het daar niet afgehandeld, dan alleen
nog naar `active_widgets` en vensters met `is_always_active`. Een schermvullend
homescreen dat alle gebaren afvangt houdt dus het menu van de bestandsbeheerder dicht,
zonder haak.

## Tikzones (`frontend/ui/widget/container/inputcontainer.lua`)

- `InputContainer:registerTouchZones(zones)`: elke zone heeft `id`, `ges`,
  `screen_zone` (ratio's 0..1), `handler`, optioneel `overrides`.
- `overrides = {"x"}` betekent: deze zone wordt **vóór** zone `x` geprobeerd
  (`DepGraph:addNodeDep(x, deze)`, `frontend/depgraph.lua`). Een zone die nog niet
  bestaat mag genoemd worden: de knoop wordt dan alvast aangemaakt.
- `InputContainer:onGesture`: loopt de geordende lijst af. De eerste zone die past
  **en `true` teruggeeft** wint. Geeft een handler `nil`/`false` terug, dan gaat het door
  naar de volgende zone.
- Opnieuw registreren met hetzelfde id vervangt de zone. `unRegisterTouchZones(zones)`
  haalt ze weg.
- In de lezer worden zones op `ReaderUI` geregistreerd (`self.ui:registerTouchZones`).
  `ReaderUI:onScreenResize` werkt ze bij via `updateTouchZonesOnScreenResize`.

### Zone-id's in de lezer (gecontroleerd)

| id | bestand | wanneer geregistreerd |
|---|---|---|
| `tap_forward`, `tap_backward` | `readerrolling.lua` / `readerpaging.lua` | init |
| `rolling_swipe`, `rolling_pan`, `rolling_pan_release` | `readerrolling.lua` | init |
| `paging_swipe`, `paging_pan`, `paging_pan_release` | `readerpaging.lua` | init |
| `readermenu_tap`, `_ext_tap`, `_swipe`, `_ext_swipe`, `_pan`, `_ext_pan` | `readermenu.lua` `ReaderMenu:initGesListener` | `onReaderReady` |
| `readerconfigmenu_tap`, `_ext_tap`, `_swipe`, `_ext_swipe`, `_pan`, `_ext_pan` | `readerconfig.lua` `ReaderConfig:initGesListener` | `onReaderReady` |
| `readerfooter_tap`, `readerfooter_hold` | `readerfooter.lua` | init |
| `tap_link`, `swipe_link` | `readerlink.lua` `ReaderLink:init` | init |
| `readerhighlight_tap`, `_tap_select_mode`, `_hold`, `_hold_release`, `_hold_pan` | `readerhighlight.lua` | init |
| `tap_top_left_corner`, `tap_top_right_corner`, `hold_top_*`, `double_tap_top_*`, `two_finger_tap_top_*`, `one_finger_swipe_top_edge_*`, … | `plugins/gestures.koplugin/main.lua` `Gestures:setupGesture` | init |

Standaardafmetingen (`defaults.lua`, te lezen met `G_defaults:readSetting(...)`):

```
DTAP_ZONE_MENU       = {x = 0,   y = 0,   w = 1,   h = 1/8}
DTAP_ZONE_MENU_EXT   = {x = 1/4, y = 0,   w = 2/4, h = 1/5}
DTAP_ZONE_CONFIG     = {x = 0,   y = 7/8, w = 1,   h = 1/8}
DTAP_ZONE_CONFIG_EXT = {x = 1/4, y = 4/5, w = 2/4, h = 1/5}
DTAP_ZONE_TOP_LEFT   = {x = 0,   y = 0,   w = 1/8, h = 1/8}   (en TOP_RIGHT, BOTTOM_*)
```

Let op: de `_EXT`-zones van menu en onderpaneel steken in het middengebied. Onze
middenzones moeten daarom ook `readermenu_ext_tap` en `readerconfigmenu_ext_tap`
overriden.

Bestaande voorrang: `tap_link` en `readerhighlight_tap` overriden zelf
`tap_forward/backward`, de menuzones en de hoekzones van gestures. Links en bestaande
markeringen gaan standaard dus vóór bladeren.

### Bovenmenu van de lezer (`frontend/apps/reader/modules/readermenu.lua`)

- `ReaderMenu:onTapShowMenu(ges)`, `ReaderMenu:onSwipeShowMenu(ges)` (opent alleen bij
  `ges.direction == "south"`), beide roepen `ReaderMenu:onShowMenu()` aan.
- `onShowMenu` is ook het event `ShowMenu` (Dispatcher-actie, toets "Menu").
  Een vangnet op instantieniveau (`self.ui.menu.onShowMenu` vervangen) houdt het
  menu dicht, hoe het ook wordt aangevraagd.
- `activate_menu` (`G_reader_settings`, `"swipe_tap"` standaard) bepaalt tik/veeg.

### Onderpaneel (`frontend/apps/reader/modules/readerconfig.lua`)

`ReaderConfig:onShowConfigMenu()` (event `ShowConfigMenu`). Blijft ongewijzigd.

### Gestures-plugin (`plugins/gestures.koplugin/main.lua`)

- `Gestures:init` registreert alle zones meteen (niet bij ReaderReady).
- Instellingen: `settings/gestures.lua`, standaardwaarden in `defaults.lua`.
  Standaard in de lezer: `tap_top_left_corner = toggle_page_flipping`,
  `tap_top_right_corner = toggle_bookmark`, `tap_left_bottom_corner = toggle_frontlight`,
  plus multiswipes (toc, bookmarks, enz.).
- `Gestures:gestureAction` geeft `nil` terug als een gebaar geen actie heeft; dan gaat
  het gebaar door naar de volgende zone.
- Overschrijft `InputContainer.isGestureAlwaysActive` (alleen relevant voor
  "touch input uit").

## Bestandsbeheerder

`frontend/apps/filemanager/filemanagermenu.lua`
- `FileManagerMenu:onShowMenu(tab_index)`: opent het volledige menu. Dat is de ingang
  voor het noodluik (`FileManager.instance.menu:onShowMenu()`).
- `FileManagerMenu:registerToMainMenu(widget)`: de plugin levert
  `addToMainMenu(menu_items)`. Een item dat niet in
  `frontend/ui/elements/filemanager_menu_order.lua` staat wordt "orphan": met
  `sorting_hint = "tools"` komt het in het Tools-tabblad, anders bovenaan met "NEW:".
  (`frontend/ui/menusorter.lua`)
- `FileManager.instance`: de actieve bestandsbeheerder.

## Boekgegevens voor het homescreen

- `frontend/readhistory.lua`: `ReadHistory.hist[1].file` is het recentste boek;
  `G_reader_settings:readSetting("lastfile")` ook.
- `frontend/ui/widget/booklist.lua`: `BookList.getDocSettings(file)`,
  `BookList.getBookInfo(file)`, `BookList.hasBookBeenOpened(file)`.
- `frontend/apps/filemanager/filemanagerbookinfo.lua`: `BookInfo:getDocProps(file)`
  (titel/auteur), `BookInfo:getCoverImage(document, file)`.
  (Uitwerken in fase 3.)

## Netwerk (`frontend/ui/network/manager.lua`)

`NetworkMgr:isOnline()`, `isWifiOn()`, `runWhenOnline(cb)`, `runWhenConnected(cb)`,
`willRerunWhenOnline(cb)`, `turnOnWifiAndWaitForConnection(cb)`, `toggleWifiOn/Off`.
`Device:hasSeamlessWifiToggle()` is op Kobo waar en in de Flatpak (SDL) **onwaar**.
(Uitwerken in fase 4.)

## OPDS-plugin (`plugins/opds.koplugin/`)

- Instellingen: `settings/opds.lua` (`LuaSettings`), sleutels `servers`, `downloads`,
  `pending_syncs`, `settings`. Een server is
  `{ title, url, username, password, sync, raw_names }`. **Het wachtwoord staat daar in
  platte tekst**; zo slaat KOReader het zelf op.
- Ontbreekt `servers`, dan vult de plugin `default_servers` in (Gutenberg enz.).
- Op deze installatie staat al server 7: `title = "Lingering"`,
  `url = "https://opds.lingering.app"`, `username = "arno"`, `sync = true`.
- `opdsbrowser.lua` (een `Menu`):
  - `OPDSBrowser:fetchFeed(url)`, `:parseFeed(url)` (OPDS 1 via `opdsparser.lua`, OPDS 2 als JSON),
    `:genItemTableFromURL(url)`, `:updateCatalog(url)`, `:onMenuSelect(item)`,
    `:onReturn()`, `:onNextPage()`.
  - Gebruikersnaam en wachtwoord komen uit `root_catalog_username/password`.
  - Downloaden: `:showDownloads(item)` (keuzedialoog), `:downloadFile(local_path, url, user, pass, cb)`,
    `:getLocalDownloadPath()`, `OPDSBrowser.getFiletype(link)`.
  - `fetchFeed` toont zelf een `InfoMessage` bij een HTTP-fout.
- `main.lua`: `OPDS:onShowOPDSCatalog()` (event `ShowOPDSCatalog`, Dispatcher
  `opds_show_catalog`); alleen in de bestandsbeheerder.
  (Uitwerken in fase 4/5.)

## Kosync-plugin (`plugins/kosync.koplugin/`)

- `is_doc_only = true`: draait alleen in de lezer.
- Instellingen: **`settings/kosync.lua`** (niet in `settings.reader.lua`), sleutel
  `settings` met `custom_server`, `username`, `userkey`, `auto_sync`,
  `pages_before_update`, `sync_forward`, `sync_backward`, `checksum_method`,
  `send_metadata`, `kosync_hostname`.
- `userkey = md5(password)` met `require("ffi/sha2").md5`, hex-string (`KOSync:doLogin`).
- Inloggen controleren: `KOSyncClient:new{custom_url=…, service_spec=<kosync-pad>/api.json}`
  en `client:authorize(username, userkey)`.
- Strategie: `SYNC_STRATEGY = {PROMPT = 1, SILENT = 2, DISABLE = 3}`.
  **`sync_forward` geldt voor een *nieuwere* stand (tijdstempel van de server is later
  dan de laatste lokale paginawissel), niet voor een stand die *verder in het boek* ligt.**
  Alleen bij een oude server zonder tijdstempel wordt op percentage vergeleken.
  (`KOSync:getProgress`)
- `auto_sync` wordt bij `init` **teruggezet naar false** als
  `Device:hasSeamlessWifiToggle()` waar is en `wifi_enable_action ~= "turn_on"`
  (`KOSync:init`). Op een Kobo moet `wifi_enable_action = "turn_on"` dus aan.
- Met `auto_sync`: `onReaderReady` haalt op, `CloseDocument` pusht (of zet in de wachtrij
  als je offline bent), en `Suspend`/`Resume`/`NetworkConnected` werken mee
  (`KOSync:registerEvents`).
- Dispatcher-acties: `kosync_push_progress` (event `KOSyncPushProgress`),
  `kosync_pull_progress` (`KOSyncPullProgress`), `kosync_toggle_autosync`,
  `kosync_set_autosync` (`KOSyncToggleAutoSync`).
- Op deze installatie: `custom_server = "https://koreader.lingering.app"`,
  `auto_sync = true`, `sync_forward = 1` (vragen), `sync_backward = 3` (uit).

## Haken die Lingering gebruikt

(Elke haak staat in `koreader/` en loopt via `koreader/try.lua`.)

| Haak (`koreader/<bestand>.<functie>`) | Waar in KOReader | Terugval als het faalt |
|---|---|---|
| `koreader/reader.buildZones` + `koreader/reader.registerZones` | `InputContainer:registerTouchZones` met `overrides`; zone-id's uit de tabel hierboven; maten uit `G_defaults` (`DTAP_ZONE_MENU`, `_MENU_EXT`, `_CONFIG`) | Zones weer verwijderd; standaard tikzones van KOReader; menu **niet** geblokkeerd |
| `koreader/reader.verifyZoneOrder` | leest `InputContainer._ordered_touch_zones` (intern) | Alleen een waarschuwing in de log |
| `koreader/reader.blockMenu` | vervangt `onShowMenu`, `onTapShowMenu`, `onSwipeShowMenu` op de `ReaderMenu`-instantie (`ui.menu`) | Bovenmenu blijft bereikbaar via andere routes dan onze zones |
| `koreader/navigation.closeBook` | `ReaderUI:onHome()`, anders `ReaderUI:onClose()` + `showFileManager()` | Tik in het midden doet niets |
| `koreader/reader.turnPage` | event `GotoViewRel` (afgehandeld door `ReaderRolling`/`ReaderPaging:onGotoViewRel`) | Tik links/rechts doet niets |
| `app/sync_service.reconcile` | "verder wint, nooit blind wegschrijven": momentopname (digest/progress/percent/metadata) → `KOSyncClient:get_progress` → server verder: `kosync:syncToProgress` (als springen mag), apparaat verder of geen stand: `update_progress`, ophalen mislukt: niets | Niet gesynchroniseerd (veilig) |
| `app/sync_service.syncNow` (sync-knop) | wifi aan (`turnOnWifiThen`), `reconcile` met springen, wifi weer uit als hij uit stond | Melding "Synchroniseren mislukt" |
| `koreader/kosync.installRules` | op de kosync-instantie: `getProgress` (openen/ontwaken/nieuwe verbinding) → offline overslaan, anders `reconcile` (1× opnieuw na 3 s); `updateProgress` (slaapstand/tussentijds) → alleen met verbinding `reconcile` zonder springen, nooit wifi aan; `_onCloseDocument` → online `reconcile`, offline niets; `drainQueue` → niets. Interactief (kosync-menu) blijft origineel | Kosync-standaard: "nieuwer wint", blind wegschrijven |
| `koreader/kosync.ensureBinary` | `kosync.settings.checksum_method = 0` (binary) | Digest op bestandsnaam |
| `koreader/device.isFrontlightOn` | `Device:getPowerDevice():isFrontlightOn()` (`BasePowerD`) | Schakelaar toont "uit" |
| `koreader/device.toggleFrontlight` | event `ToggleFrontlight` (`frontend/device/devicelistener.lua`, `DeviceListener:onToggleFrontlight`) | Knop doet niets |
| `koreader/device.hasFrontlight` / `hasWifiToggle` / `isTouchDevice` / `timeText` | `Device:hasFrontlight/hasWifiToggle/isTouchDevice`, `datetime.secondsToHour` met `twelve_hour_clock` | Schakelaars grijs; tijd als `%H:%M` |
| `koreader/locale.language` / `setting` / `change` | `GetText.current_lang`, `G_reader_settings` "language", `Language:changeLanguage` (bewaart en vraagt om herstart) | Lingering Engels; Taal-scherm doet niets |
| `koreader/dictionaries.entry` / `isInstalled` / `isEnabled` / `download` / `choose` | KOReaders lijst `ui/data/dictionaries.lua` (op naam uit `config.dictionaries`), `fm.dictionary:downloadDictionary` (in `Trapper:wrap`; bevestiging met grootte, uitpakken in `<data_dir>/<veilige naam>`), aan/uit via `G_reader_settings` `dicts_disabled` (sleutel = .ifo-pad), zoals `ReaderDictionary:showDictionariesMenu` | Scherm Woordenboek toont alles als "downloaden"; kiezen doet niets |
| `koreader/device.brightnessRange` / `brightness` / `setBrightness` | `BasePowerD.fl_min/fl_max`, `frontlightIntensity`, `setIntensity` / `turnOffFrontlight`, `updateResumeFrontlightState` (zoals `FrontLightWidget:setFrontLightIntensity`); KOReader bewaart de stand zelf | Schuif doet niets |
| `koreader/books.readingBooks` | `ReadHistory.hist`, `BookList.getDocSettings` (`percent_finished`, `summary.status` zoals `BookList.getBookStatus`), `FileManagerBookInfo:getDocProps/getCoverImage`. Aan het lezen = status `reading` (niet on hold/uit), hooguit 4, hetzelfde boek in meer bestanden één keer (zelfde `partial_md5_checksum` of titel+auteur; recentste wint); niets aan het lezen → het laatst geopende boek. Homescreen: 1 boek = grote kaart, 2–4 = rij in het raster van Mijn boeken | Homescreen zonder boek ("Nog geen boek") |
| `koreader/books.markFinished` / `syncPosition`, `koreader/kosync.storeFinished` | `summary.status = "complete"` + `filemanagerutil.saveSummary` + `BookList.setBookInfoCacheProperty` (zoals KOReaders statusknoppen); `partial_md5_checksum` en `last_xpointer`/`last_page`; `KOSyncClient:update_progress` met percentage 1 | "Gelezen" doet niets of alleen lokaal |
| `koreader/device.rotateWithinOrientation` | `Screen:setRotationMode` + `UIManager:onRotation` (zoals `Input:handleGyroEv` met vergrendelde g-sensor); `fm_rotation_mode` voor `FileManager:setRotationMode`. Aangeroepen vanuit `onSetRotationMode` van onze schermen (`Widgets.followRotation`): `SetRotationMode` gaat alleen naar het bovenste venster. Alleen binnen dezelfde stand | Scherm draait niet mee |
| `koreader/device.setAutoRotate` / `isAutoRotateOn` | `input_ignore_gsensor` + `Device:toggleGSensor` (zoals `DeviceListener:onToggleGSensor`, zonder melding) | Schakelaar doet niets |
| Actiebalk (`actionbar.lua`) | geen haak: eigen `InputContainer` met `Button`s, getoond met `UIManager:show` | — |
| `koreader/navigation.showFullMenu` | `FileManagerMenu:onShowMenu()` | Noodluik opent niet; de gewone bestandsbeheerder blijft zichtbaar |
| `koreader/global_settings.enforce` | `G_reader_settings`: `start_with` (`reader.lua`), `screensaver_type`, `screensaver_show_message`, `screensaver_hide_cover_in_filemanager`, `screensaver_hide_fallback_msg` (`frontend/ui/screensaver.lua`, `Screensaver:setup`). Eenmalige back-up `settings.reader.lua.lingering-backup` | Instellingen blijven zoals ze waren |
| `koreader/books.currentBook` | `ReadHistory.hist` (eerste bestaande, geen `<datadir>/help/quickstart-*.html`), `BookList.getDocSettings(file):readSetting("percent_finished")`, `fm.bookinfo:getDocProps(file, nil, true)`, `fm.bookinfo:getCoverImage(nil, file)` | Homescreen zonder boek ("Nog geen boek"), of zonder omslag |
| `koreader/books.stats` | statistics-plugin: alleen als `fm.statistics.settings.is_enabled`; database `<settings>/statistics.sqlite3` (`lua-ljsqlite3/init`), tabel `book` op `md5 = partial_md5_checksum`, gecapte totalen zoals `STATISTICS_SQL_BOOK_CAPPED_TOTALS_QUERY` met `settings.max_sec`; resterend = (pages − percent×pages) × gemiddelde (zoals `getCurrentStat`) | Regel met "x% gelezen" in plaats van tijden |
| `koreader/navigation.openBook` | `ReaderUI:showReader(file)` | Tik op het boek doet niets |
| `koreader/device.batteryPercent`, `koreader/network.isWifiOn`, `koreader/network.isConnected`, `koreader/network.setWifi` | `Device:getPowerDevice():getCapacity()`, `NetworkMgr:isWifiOn()` (radio, voor de schakelaar), `NetworkMgr:isConnected()` (verbinding, voor het icoon; op Kobo `ifHasAnAddress`), `NetworkMgr:toggleWifiOn/Off` | Statusregel zonder batterij/wifi; wifi-schakelaar doet niets |
| Statusregel homescreen | lamp: `toggleFrontlight(fm)` (FileManager heeft ook een `DeviceListener`); wifi: `setWifi` + `isWifiOn`/`isWifiConnected`; iconen via `ActionBar.Item` (switch met `icon_spec`) | Iconen grijs/zonder effect |
| Homescreen tonen | eigen widget via `UIManager:show` vanuit `init` in FileManager-context (`nextTick`); sluit zichzelf bij event `ShowingReader` | Gewone bestandsbeheerder blijft zichtbaar |
| `koreader/opds.check` | eigen GET met `socket.http` + `socketutil` (zoals `OPDSBrowser:fetchFeed`, maar zonder eigen melding) | Inloggen meldt "mislukt bij de bibliotheek" |
| `koreader/kosync.check` | `KOSyncClient:new{custom_url, service_spec}` + `client:authorize(user, md5(pass))`; `api.json` naast `KOSyncClient.lua` (`package.searchpath`) | Inloggen meldt "mislukt bij de syncserver" |
| `koreader/opds.writeAccount` | `<settings>/opds.lua` → `servers` (bijwerken op gelijk adres, anders toevoegen); geladen `fm.opds.servers` krijgt dezelfde wijziging | Melding "kon niet worden opgeslagen" |
| `koreader/kosync.writeAccount` | `<settings>/kosync.lua` → `settings`; gedeeld `KOSync.settings_obj` via `PluginLoader.enabled_plugins` als kosync al geladen was | idem |
| `koreader/dialogs.plainDialog` | na `MultiInputDialog:init`: `dialog_frame.bordersize = 0`, `title_bar` uit de eerste `VerticalGroup` (subklasse `LoginDialog` in `setup.lua`, zodat het ook na een herbouw geldt) | Gewoon KOReader-venster met rand en titel |
| `koreader/network.turnOnWifiThen` | `NetworkMgr:isOnline()`, anders `NetworkMgr:turnOnWifiAndWaitForConnection(cb)` (zonder te vragen) | Melding "Geen wifi-verbinding" |
| `koreader/device.showLightDialog` | `Device:showLightDialog()` (KOReaders `FrontLightWidget`); helderheid onthoudt KOReader zelf (`frontlight_intensity`); iconen volgen het event `FrontlightStateChanged` (`BasePowerD:stateChanged`) | Rij "Licht" doet niets |
| `koreader/network.showNetworkList` | KOReaders netwerkscherm (`ui/widget/networksetting`) zoals lang drukken op "Wi-Fi connection" (`NetworkMgr:getWifiToggleMenuTable`): wifi uit → `toggleWifiOn(cb, true, true)`; wifi aan → `wifi_toggle_long_press = true` + `reconnectOrShowNetworkMenu(cb, true)` | Rij "Wifi" doet niets |
| `koreader/global_settings.ensureAutoWifi` | `wifi_enable_action = "turn_on"` alleen als `Device:hasSeamlessWifiToggle()` (zie `KOSync:init`) | Auto-sync kan door kosync worden uitgezet |
| `koreader/opds.credentials`, `koreader/opds.client`, `koreader/opds.fetchPage`, `koreader/opds.filetype`, `koreader/opds.download` | `opds.lua`-servers; kaal object met metatable `OPDSBrowser` (`sync = true`); `genItemTableFromURL`, `OPDSBrowser.getFiletype`, `downloadFile` | Mijn boeken toont alleen de cache / downloaden mislukt |
| `koreader/books.homeFolder`, `koreader/network.isOnline` | `filemanagerutil.getHomeFolder()`, `NetworkMgr:isOnline()` | Downloads in `./Lingering`; geen automatische sync |
| Menu-item `lingering_disable` | `FileManagerMenu:registerToMainMenu` + `addToMainMenu`, `sorting_hint = "main"` | Geen haak: standaard plugin-API |

Woordenboek:
- Instellingen → Woordenboek: Nederlands of Engels (`config.dictionaries`, op naam uit
  KOReaders lijst, zodat KOReader de links bijhoudt). Tik: staat het er niet op, dan wifi aan,
  KOReaders eigen download (met bevestiging), daarna kiezen. Kiezen zet het gekozen
  woordenboek aan en het andere van de twee uit; zelf geplaatste woordenboeken blijven zoals
  ze zijn.

Taal:
- Bronteksten zijn Nederlands, in `_()` uit `lingering.l10n.gettext` (niet KOReaders
  gettext: die kent onze teksten niet). Staat KOReader op Nederlands (`nl*`), dan
  Nederlands; anders Engels uit `l10n/en.lua`. De taal komt uit `GetText.current_lang`
  (`koreader/locale.lua`); zonder ingestelde taal is KOReader Engels ("C").
- `tools/check_l10n.lua` (in `check.sh`) faalt als een `_("…")` geen Engelse vertaling heeft.
- Instellingen → Taal (Nederlands / English) zet KOReaders taal, zoals KOReaders taalmenu;
  na de herstart volgen KOReader en Lingering die taal.
- `_meta.lua` wordt vóór main.lua gelezen (zonder onze loader) en kiest de taal zelf.
- Mapnamen uit de OPDS-catalogus (`config.collections`) worden niet vertaald: daaraan
  worden de mappen herkend.

Raster:
- `ui/grid.lua`: vaste marge aan de schermrand, vaste tussenruimte tussen kolommen, vaste
  rijruimte; per rij 1, 2 of 4 kolommen (`Grid.rows`). Homescreen: rij 1 = boek (1 kolom) of
  boeken (4), rij 2 = mappen (2). Mijn boeken: mappen in rijen van 2, boeken in rijen van 4;
  met schuifbalk krijgt het raster de breedte náást de schuifbalk (marges links en rechts gelijk).
- Mappen zijn overal `ui/folder_tile.lua`: waaier van tot 4 omslagen over de kolombreedte
  (achterste steeds 88%), naam en grijs het aantal boeken, links uitgelijnd.

Boekmenu:
- Op het homescreen heeft elk boek (rij en grote kaart) rechts een grijze "⋮"-knop (Material more_vert) met een
  menu (`ui/popover_menu.lua`, herbruikbaar). Nu één item: Gelezen → `SyncService.markFinished`:
  in KOReader op uit (verdwijnt uit de rij) en, met verbinding, 100% naar de syncserver
  (nooit wifi aanzetten; 100% is nooit achteruit).

Stijl:
- Alle kleuren, lijnen, randen en de maten van de bovenbalk staan in `ui/style.lua`
  (`Style.line`, `Style.text_secondary`, `Style.top_bar`, …). Schermen en widgets halen hun
  waarden daar vandaan; geen losse `Blitbuffer.COLOR_*` of `Size.line.*` in de schermen.

Navigatie tussen de schermen:
- Homescreen, Mijn boeken, Instellingen en Over Lingering hebben dezelfde navigatiebalk
  onderaan (`Widgets.mainNav`: Home, Mijn boeken, Instellingen); het leesscherm niet. Het
  actieve tabblad staat vet. Home sluit de bijgehouden schermen; het homescreen ligt eronder.
- Een wissel gaat via `Lingering:switchTo` (main.lua): eerst gaan de bijgehouden schermen
  (`Lingering:track`) dicht, dan opent het nieuwe. Zo ligt er altijd hooguit één tabblad
  (met eventueel Over Lingering) op het homescreen, en gaat terug altijd naar het homescreen.
- Tik op het actieve tabblad: Mijn boeken gaat terug naar het begin, Over Lingering sluit
  (terug naar Instellingen).
- `tools/smoke.sh` start de emulator met een vast formaat (758×1024): KOReader onthoudt de
  venstergrootte (`sdl_window`), en op een ander formaat valt de indeling anders uit.

Bewuste keuzes in het leesscherm:
- Onze tikzones gaan ook vóór `tap_link` en `readerhighlight_tap`: een tik doet altijd wat
  de zone zegt, ook op een link of markering.
- Tik in de strook bovenaan opent de eigen actiebalk: dezelfde statusbalk als op het
  homescreen (`ui/statusbar.lua`), met huis en inhoudsopgave links, en sync en automatisch
  draaien rechts vóór licht, wifi, batterij en tijd.
- Tik op het batterij-icoon (homescreen en boek): klein kader eronder met het percentage
  en "Laadt op" (`ui/popover.lua`, rand `Style.line`, modal zodat het boven de actiebalk komt;
  sluit bij een tik of na 4 s).
- Tik op het licht-icoon: licht aan of uit, zoals op de Kobo zelf. Gaat het aan, dan meteen
  een kader met een schuif (`ui/slider.lua`: − [balk] +; tik op de balk springt naar die
  stand, geen slepen). Helemaal links = uit. Via `koreader/device.setBrightness`
  zoals KOReaders `FrontLightWidget:setFrontLightIntensity`. Het kader blijft 8 s open na de
  laatste tik. Grijze lijn eronder (`Style.line`) tegen de tekst van het boek.
  Alle iconen komen uit `icons/` (Material Symbols, één stijl), via `IconWidget{file=…}`; geen iconen
  uit KOReader's eigen set. Daarom ook een eigen titelbalk (`Widgets.header`): KOReader's
  `TitleBar`/`IconButton` kennen alleen iconnamen uit hun eigen mappen. Het sync-icoon draait
  tijdens het synchroniseren in 4 frames (`sync*.svg`, 45° per stap, elke 0,4 s, alleen
  dat vak met `"fast"`-verversing; het laatste frame met `"ui"`). Dit wijkt bewust af van
  "geen animaties" op verzoek. Vegen bovenaan doet niets.
- Tikzone-handlers en knop-callbacks vallen **niet** onder de `HandlerSandbox` van de
  pluginloader; Lingering wikkelt ze zelf in `pcall`.
- Omgekeerde leesrichting (`inverse_reading_order`) wordt genegeerd: links is altijd terug.
- Ingedrukt houden in de hoeken bovenaan valt niet onder "niets": de gestures-plugin
  heeft daar standaard geen actie, en de hold is nodig voor het woordenboek.

Slaapscherm (`Screensaver:setup`): bij `screensaver_type = "cover"` wordt de omslag van
`lastfile` getoond. Valt dat weg (geen boek, geen omslag, boek uitgesloten), dan gebruikt
KOReader `random_image`, met `resources/koreader.png` als laatste terugval. In de
bestandsbeheerder (dus op het homescreen) sluit `screensaver_hide_cover_in_filemanager` de
omslag uit; Lingering zet die op false.

Netwerk-events (`NetworkConnected`, `NetworkDisconnected`, `NetworkConnecting`,
`NetworkDisconnecting`) en `Suspend`/`Resume` gaan via `UIManager:broadcastEvent` naar
**alle** vensters, ook als een ander scherm erbovenop ligt
(`frontend/ui/network/manager.lua`, `frontend/device/generic/device.lua`).
Op de desktop (SDL) geven `isWifiOn`/`isConnected` altijd `true` en is
`hasWifiToggle` onwaar.

## Vensterstapel en `modal`

`UIManager:show` zet een niet-modaal venster **onder** het bovenste modale venster
(`frontend/ui/uimanager.lua`). `MultiInputDialog` is niet modaal. Onze schermvullende
schermen (homescreen, instellingen, inlog-achtergrond) zijn daarom niet `modal`; anders
verdwijnen dialogen van KOReader eronder.

## Volgorde van plugins

`PluginLoader:loadPlugins` sorteert op **pad**. Onze map `<datadir>/plugins/lingering.koplugin`
(absoluut, begint met `/`) komt vóór de ingebouwde `plugins/…`. In `init` bestaan
`ui.kosync`, `ui.gestures` enz. dus nog niet; `onReaderReady` van Lingering draait ook vóór
die van kosync. Kosync plant zijn eerste `getProgress` met `UIManager:nextTick`.

## Voortgang (fase 6, herzien)

Regel: **verder wint, nooit blind wegschrijven** (op verzoek, na een echte overschrijving:
boek via OPDS gedownload, geopend, sync → oudere stand van de Kobo overschreef een verdere).
Kosync zelf vergelijkt op tijdstempel (`KOSync:getProgress`, "nieuwer wint") en schrijft bij
sluiten/slaapstand/wachtrij blind weg; dat is via `installKosyncRules` vervangen.

| Moment | Gedrag |
|---|---|
| Openen / ontwaken met verbinding | `reconcile` met springen |
| Openen / ontwaken zonder verbinding | overslaan |
| Sync-knop | wifi aan → `reconcile` met springen → wifi uit (als hij uit stond) |
| Sluiten met verbinding | `reconcile` zonder springen |
| Sluiten zonder verbinding | niets (geen wachtrij) |
| Slaapstand met verbinding | `reconcile` zonder springen → wifi uit |
| Slaapstand zonder verbinding | niets (wifi gaat niet aan; op verzoek) |

Getest tegen een echte server: gelijk → niets; 5 pagina's verder → wegschrijven;
5 pagina's terug → vooruit springen.

## Mijn boeken (fase 5)

- `library.lua`: cache per gebruiker in `<datadir>/cache/lingering/library.lua`
  (`feeds[gebruiker][adres] = { items, fetched }`), omslagen in `.../covers/<md5(url)>`.
  Ophalen via `Compat.opdsFetchPage` (= `OPDSBrowser:genItemTableFromURL`), alle
  `hrefs.next`-pagina's, één verzoek per UIManager-tik. Items worden genormaliseerd tot
  `{kind="folder", title, url}` of `{kind="book", title, author, thumbnail, href, filetype}`
  (EPUB heeft voorkeur, via `OPDSBrowser.getFiletype`).
- Downloaden via `OPDSBrowser:downloadFile` naar `<thuismap>/Lingering/<titel - auteur>.<ext>.part`,
  daarna hernoemd; "gedownload" = het bestand bestaat.
- Omslagen: eigen stille `socket.http`-GET (geen meldingen per mislukte omslag), en zelf
  decoderen met `RenderImage:renderImageFile` in een `pcall` (kapotte afbeelding wordt
  verwijderd in plaats van het scherm te breken).
- `Item.on_tap` (actionbar.lua) loopt nu ook via `safeCall`.
- Taak-iconen (sync): eerste frame tekenen met `UIManager:forceRePaint()`, de taak pas in
  `UIManager:nextTick` starten, en minstens 1,2 s laten draaien. Netwerkverzoeken via
  `socket.http` blokkeren de enige thread; tijdens één verzoek staat het icoon stil.
- Raster: boeken in 4 kolommen zonder titel (titel en auteur alleen in het vak van een boek
  zonder omslag), collecties in 2 kolommen met naam, getekend als stapel van tot drie
  omslagen uit die map (`Widgets.coverStack`, herbruikbaar; `Widgets.stackSize` /
  `stackCoverSize`). Ongeladen mappen worden met wifi op de achtergrond geladen
  (`LibraryScreen:prefetchFolders`, één keer per map); lege mappen: klein mapicoon.

## Tekenen en vangnetten

Fouten in `paintTo` en in met `UIManager:scheduleIn/nextTick` ingeplande functies vangt
KOReader **niet** af: ze laten KOReader crashen (gezien in fase 3: een `VerticalGroup`
waarvan `getSize()` werd opgevraagd vóór er elementen bij kwamen). `Widgets.guardPaint`
wikkelt `paintTo` van homescreen, instellingen en actiebalk in `pcall` en sluit het scherm
bij een fout.

Let op bij `VerticalGroup`/`HorizontalGroup`: `getSize()` onthoudt maten en posities.
Na wijzigen eerst `resetLayout()`.

## Modules laden

`package.path` begint met `common/?.lua;frontend/?.lua;…;./?.lua`, en pluginmappen staan
erachter. Bovendien is de cache van `require` voor alle plugins gedeeld. `require("reader")`
zou dus KOReader's eigen `reader.lua` laden. Daarom zet `main.lua` onze bestanden in
`package.preload` onder `lingering_<naam>` en laadt ze met `dofile` uit de eigen map.
