// Run with the Codex Computer Use node_repl and @oai/sky available.
// This intentionally uses accessibility identifiers where possible and fails
// loudly when a key product flow is missing from the UI.

var app = globalThis.timeslotSmokeApp ?? "/Applications/时隙.app";
var state = await sky.get_app_state({ app, disableDiff: true });

function requireText(label, expected) {
    if (!state.text.includes(expected)) {
        throw new Error(`${label}: missing “${expected}”`);
    }
}

function requireSingle(label, expected) {
    var count = state.text.split(expected).length - 1;
    if (count !== 1) {
        throw new Error(`${label}: expected one “${expected}”, found ${count}`);
    }
}

function indexForIdentifier(identifier) {
    var escaped = identifier.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    var match = state.text.match(new RegExp("(\\d+)[^\\n]*ID: " + escaped));
    if (!match) {
        throw new Error(`missing accessibility identifier “${identifier}”`);
    }
    return Number(match[1]);
}

await sky.click({ app, element_index: indexForIdentifier("square.grid.2x2") });
state = await sky.get_app_state({ app, disableDiff: true });

requireText("launch", "时隙");
requireText("countdown page", "倒计时");
var menuBarStart = state.text.indexOf("menu bar");
var menuBarText = menuBarStart >= 0 ? state.text.slice(menuBarStart) : "";
var helpMenuCount = menuBarText.split("帮助").length - 1;
if (helpMenuCount !== 1) {
    throw new Error(`native help menu: expected one top-level menu, found ${helpMenuCount}`);
}

await sky.click({ app, element_index: indexForIdentifier("timeslot.settings.open") });
state = await sky.get_app_state({ app, disableDiff: true });
requireText("settings page", "提醒、小组件与专注节奏");
requireText("notification state", "系统通知");
requireText("widget settings", "桌面小组件");

await sky.click({ app, element_index: indexForIdentifier("timer") });
state = await sky.get_app_state({ app, disableDiff: true });
requireText("pomodoro page", "番茄钟");
requireText("pomodoro focus workspace", "当前任务");

var insightsIndex = state.text.match(/(\d+) 按钮[^\n]*ID: timeslot\.segment\.pomodoro\.insights/);
if (!insightsIndex) {
    throw new Error("pomodoro insights control is not exposed to accessibility");
}
await sky.click({ app, element_index: Number(insightsIndex[1]) });
state = await sky.get_app_state({ app, disableDiff: true });
requireText("pomodoro insights workspace", "阶段记录");
requireText("history filter", "查看时间范围");

nodeRepl.write("时隙 UI 冒烟测试通过：启动、帮助菜单、设置、通知状态、番茄钟与阶段记录均可访问。\n");
