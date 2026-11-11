pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: root

    property bool smartTray: Config.options.tray.filterPassive
    readonly property var availableItems: SystemTray.items.values.filter(i => !smartTray || i.status !== Status.Passive)
    readonly property var itemsInUserList: availableItems.filter(i => Config.options.tray.pinnedItems.includes(i.id))
    readonly property var itemsNotInUserList: availableItems.filter(i => !Config.options.tray.pinnedItems.includes(i.id))

    property bool invertPins: Config.options.tray.invertPinnedItems
    readonly property var pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    readonly property var unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList

    function getTooltipForItem(item) {
        var result = item.tooltipTitle.length > 0 ? item.tooltipTitle
                : (item.title.length > 0 ? item.title : item.id);
        if (item.tooltipDescription.length > 0) result += " • " + item.tooltipDescription;
        if (Config.options.tray.showItemId) result += "\n[" + item.id + "]";
        return result;
    }

    // Pinning
    function pin(itemId) {
        var pins = Config.options.tray.pinnedItems;
        if (pins.includes(itemId)) return;
        Config.options.tray.pinnedItems = pins.concat([itemId]);
    }
    function unpin(itemId) {
        Config.options.tray.pinnedItems = Config.options.tray.pinnedItems.filter(id => id !== itemId);
    }
    function togglePin(itemId) {
        var pins = Config.options.tray.pinnedItems;
        if (pins.includes(itemId)) {
            unpin(itemId)
        } else {
            pin(itemId)
        }
    }

}
