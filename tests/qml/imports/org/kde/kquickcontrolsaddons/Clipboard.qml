// SPDX-License-Identifier: MIT

import QtQml

QtObject {
    property int mode: 0
    property var content
    readonly property list<string> formats: {
        if (Array.isArray(content) && content.length > 0)
            return ["text/uri-list"];
        if (typeof content === "string")
            return ["text/plain"];
        return [];
    }

    function contentFormat(format) {
        if (format === "text/uri-list" && Array.isArray(content))
            return content;
        return content || "";
    }

    function clear() {
        content = undefined;
    }
}
