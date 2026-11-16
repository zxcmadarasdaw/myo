.pragma library

function escape(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function inline(text, palette) {
    const pattern = /(`[^`\n]+`|\*\*[^*\n]+\*\*|\*[^*\n]+\*|!?\[[^\]\n]+\]\([^\n)]*\))/g;
    let html = "";
    let end = 0;
    for (let token; (token = pattern.exec(text)) !== null;) {
        html += escape(text.slice(end, token.index));
        const value = token[0];
        if (value.startsWith("`")) html += "<tt style='color:" + palette.primary + "'>" + escape(value.slice(1, -1)) + "</tt>";
        else if (value.startsWith("**")) html += "<b>" + escape(value.slice(2, -2)) + "</b>";
        else if (value.startsWith("*")) html += "<i>" + escape(value.slice(1, -1)) + "</i>";
        else html += escape(value);
        end = pattern.lastIndex;
    }
    return html + escape(text.slice(end));
}

function code(text, language, palette) {
    if (!/^(?:bash|sh|shell|python|py|js|javascript|ts|typescript|qml|lua|json|c|cpp|rust|go)$/i.test(language))
        return escape(text);
    const pattern = /(#.*|\/\/.*|--.*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b\d+(?:\.\d+)?\b|\b(?:if|then|else|elseif|end|function|local|return|for|in|do|while|const|var|let|import|from|def|class|try|catch|except|true|false|null|nil|None|True|False)\b)/g;
    let html = "";
    let end = 0;
    for (let token; (token = pattern.exec(text)) !== null;) {
        html += escape(text.slice(end, token.index));
        const value = token[0];
        const color = /^(#|\/\/|--)/.test(value) ? palette.muted
            : (/^["']/.test(value) ? palette.green : (/^\d/.test(value) ? palette.peach : palette.primary));
        html += "<span style='color:" + color + "'>" + escape(value) + "</span>";
        end = pattern.lastIndex;
    }
    return html + escape(text.slice(end));
}

function render(text, palette) {
    const html = [];
    let fence = "";
    let language = "";
    let snippet = [];
    let list = "";
    function closeList() {
        if (list) html.push("</" + list + ">");
        list = "";
    }
    function closeFence() {
        html.push("<pre style='background-color:" + palette.base + ";'>" + code(snippet.join("\n"), language, palette) + "</pre>");
        snippet = [];
        fence = "";
    }
    for (const line of text.replace(/\r\n/g, "\n").split("\n")) {
        if (fence) {
            if (line.trim() === fence) closeFence();
            else snippet.push(line);
            continue;
        }
        const open = /^\s*(`{3,}|~{3,})\s*([\w+-]*)\s*$/.exec(line);
        const item = /^\s*([-*+]|\d+\.)\s+(.+)$/.exec(line);
        if (item) {
            const type = /\d/.test(item[1]) ? "ol" : "ul";
            if (list !== type) {
                closeList();
                list = type;
                html.push("<" + list + ">");
            }
            html.push("<li>" + inline(item[2], palette) + "</li>");
            continue;
        }
        closeList();
        const heading = /^(#{1,6})\s+(.+)$/.exec(line);
        if (open) {
            fence = open[1];
            language = open[2];
        } else if (heading) {
            const tag = "h" + heading[1].length;
            html.push("<" + tag + ">" + inline(heading[2], palette) + "</" + tag + ">");
        } else if (line.startsWith("> ")) {
            html.push("<blockquote>" + inline(line.slice(2), palette) + "</blockquote>");
        } else {
            html.push(line ? inline(line, palette) + "<br>" : "<br>");
        }
    }
    closeList();
    if (fence) closeFence();
    return html.join("");
}
