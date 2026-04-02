(function () {
    'use strict';

    var MAX_ACTIVITY = 50;
    var activityLog = [];
    var lastAgentStates = {};

    // Called from Swift KanbanPanel.pushAgentState()
    window.updateAgents = function (agents) {
        updateCards(agents);
        detectActivityChanges(agents);
        lastAgentStates = {};
        agents.forEach(function (a) { lastAgentStates[a.id] = a; });
    };

    function updateCards(agents) {
        var container = document.getElementById('agent-cards');
        var countEl = document.getElementById('agent-count');
        countEl.textContent = agents.length + ' agent' + (agents.length !== 1 ? 's' : '');

        if (agents.length === 0) {
            container.innerHTML = '<div class="empty-state">No agents detected</div>';
            return;
        }

        container.innerHTML = agents.map(function (a) {
            return '<div class="agent-card ' + (a.status === 'waitingForInput' ? 'attention' : '') + '">' +
                '<div class="agent-header">' +
                '<span class="agent-dot ' + a.type + '"></span>' +
                '<span class="agent-name">' + capitalize(a.type) + '</span>' +
                '</div>' +
                '<span class="agent-status ' + a.status + '">' + formatStatus(a.status) + '</span>' +
                '<div class="agent-meta">' +
                '<div>project: ' + escapeHtml(a.project || '\u2014') + '</div>' +
                '<div>pane: ' + escapeHtml(a.paneId) + '</div>' +
                '<div>uptime: ' + formatUptime(a.uptime) + '</div>' +
                '<div>last: ' + escapeHtml(a.lastFile || '\u2014') + '</div>' +
                '</div>' +
                '<div class="agent-actions">' +
                '<button onclick="focusAgent(\'' + a.paneId + '\')">Focus</button>' +
                '<button class="btn-stop" onclick="stopAgent(\'' + a.paneId + '\')">Stop</button>' +
                '</div></div>';
        }).join('');
    }

    function detectActivityChanges(agents) {
        agents.forEach(function (a) {
            var prev = lastAgentStates[a.id];
            if (!prev) {
                addActivity(a.type, 'started');
            } else if (prev.status !== a.status) {
                addActivity(a.type, formatStatus(a.status));
            } else if (prev.lastFile !== a.lastFile && a.lastFile) {
                addActivity(a.type, 'editing ' + a.lastFile);
            }
        });
    }

    function addActivity(agentType, message) {
        activityLog.unshift({
            time: new Date(),
            agent: agentType,
            message: message
        });
        if (activityLog.length > MAX_ACTIVITY) activityLog.pop();
        renderActivity();
    }

    function renderActivity() {
        var feed = document.getElementById('activity-feed');
        if (activityLog.length === 0) {
            feed.innerHTML = '<div class="empty-state">No activity yet</div>';
            return;
        }
        feed.innerHTML = activityLog.map(function (a) {
            return '<div class="activity-item">' +
                '<span class="activity-time">' + formatTime(a.time) + '</span>' +
                '<span class="activity-agent ' + a.agent + '">' + capitalize(a.agent) + '</span>' +
                '<span>' + escapeHtml(a.message) + '</span>' +
                '</div>';
        }).join('');
    }

    // Actions — communicate with Swift via WKScriptMessageHandler
    window.focusAgent = function (paneId) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cmux) {
            window.webkit.messageHandlers.cmux.postMessage({ action: 'focus-pane', paneId: paneId });
        }
    };

    window.stopAgent = function (paneId) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cmux) {
            window.webkit.messageHandlers.cmux.postMessage({ action: 'send-key', paneId: paneId, key: 'C-c' });
        }
    };

    // Utilities
    function capitalize(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : ''; }
    function escapeHtml(s) {
        if (!s) return '';
        var div = document.createElement('div');
        div.textContent = s;
        return div.innerHTML;
    }
    function formatStatus(s) {
        var map = { idle: 'Idle', thinking: 'Thinking', editing: 'Editing', runningCommand: 'Running', waitingForInput: 'Needs Input' };
        return map[s] || s;
    }
    function formatUptime(seconds) {
        if (!seconds || seconds < 60) return '<1m';
        var mins = Math.floor(seconds / 60);
        if (mins < 60) return mins + 'm';
        return Math.floor(mins / 60) + 'h ' + (mins % 60) + 'm';
    }
    function formatTime(date) {
        return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false });
    }
})();
