(function () {
    'use strict';

    let GITLAB_HOST = '';
    let GITLAB_TOKEN = '';
    let GITLAB_PROJECT = '';
    let POLL_INTERVAL = 30000;
    let pollTimer = null;

    // Tab navigation
    document.querySelectorAll('.tab').forEach(tab => {
        tab.addEventListener('click', () => {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
            tab.classList.add('active');
            document.getElementById(tab.dataset.tab).classList.add('active');
        });
    });

    // Init from Swift injection
    window.onGitLabReady = function () {
        GITLAB_HOST = window.__GITLAB_HOST__ || '';
        GITLAB_TOKEN = window.__GITLAB_TOKEN__ || '';
        document.getElementById('setting-host').value = GITLAB_HOST;
        if (GITLAB_HOST && GITLAB_TOKEN) {
            fetchMRs();
            fetchPipelines();
            startPolling();
        }
    };

    window.setGitLabProject = function (project) {
        GITLAB_PROJECT = project;
    };

    // API helper
    async function api(path, options = {}) {
        const url = GITLAB_HOST + '/api/v4' + path;
        const res = await fetch(url, {
            ...options,
            headers: {
                'PRIVATE-TOKEN': GITLAB_TOKEN,
                'Content-Type': 'application/json',
                ...(options.headers || {})
            }
        });
        if (!res.ok) throw new Error('GitLab API ' + res.status + ': ' + (await res.text()));
        return res.json();
    }

    function encodeProject() {
        return encodeURIComponent(GITLAB_PROJECT);
    }

    // MR list
    async function fetchMRs() {
        var container = document.getElementById('mrs');
        try {
            var mrs = await api('/merge_requests?state=opened&scope=assigned_to_me&per_page=20');
            if (mrs.length === 0) {
                container.innerHTML = '<div class="loading">No open merge requests assigned to you</div>';
                return;
            }
            container.innerHTML = mrs.map(function (mr) {
                return '<div class="mr-item" data-iid="' + mr.iid + '" data-project="' + mr.project_id + '">' +
                    '<div class="mr-title">' +
                    '<span class="mr-status ' + mr.state + '">' + mr.state + '</span> ' +
                    '!' + mr.iid + ' ' + escapeHtml(mr.title) +
                    '</div>' +
                    '<div class="mr-meta">' +
                    escapeHtml(mr.references ? mr.references.full : mr.web_url) +
                    ' &middot; ' + (mr.author ? mr.author.name : 'unknown') +
                    ' &middot; ' + timeAgo(mr.updated_at) +
                    '</div></div>';
            }).join('');

            container.querySelectorAll('.mr-item').forEach(function (item) {
                item.addEventListener('click', function () {
                    showMRDetail(item.dataset.project, item.dataset.iid);
                });
            });
        } catch (e) {
            container.innerHTML = '<div class="loading">Error: ' + escapeHtml(e.message) + '</div>';
        }
    }

    // MR detail
    async function showMRDetail(projectId, iid) {
        var container = document.getElementById('mrs');
        container.innerHTML = '<div class="loading">Loading...</div>';
        try {
            var results = await Promise.all([
                api('/projects/' + projectId + '/merge_requests/' + iid),
                api('/projects/' + projectId + '/merge_requests/' + iid + '/discussions')
            ]);
            var mr = results[0];
            var discussions = results[1];

            var discussionsHtml = discussions
                .filter(function (d) { return d.notes && d.notes.length; })
                .map(function (d) {
                    return d.notes.map(function (n) {
                        return '<div class="discussion">' +
                            '<div class="discussion-author">' + escapeHtml(n.author ? n.author.name : 'unknown') + ' &middot; ' + timeAgo(n.created_at) + '</div>' +
                            '<div class="discussion-body">' + escapeHtml(n.body) + '</div>' +
                            '</div>';
                    }).join('');
                }).join('');

            container.innerHTML =
                '<div class="mr-detail">' +
                '<button class="back-btn" id="back-to-mrs">&larr; Back to list</button>' +
                '<h2><span class="mr-status ' + mr.state + '">' + mr.state + '</span> !' + mr.iid + ' ' + escapeHtml(mr.title) + '</h2>' +
                '<div class="mr-meta">' + escapeHtml(mr.source_branch) + ' &rarr; ' + escapeHtml(mr.target_branch) + ' &middot; ' + (mr.author ? mr.author.name : '') + '</div>' +
                '<p style="margin:12px 0;color:var(--text-muted);">' + escapeHtml(mr.description || 'No description') + '</p>' +
                '<div style="display:flex;gap:8px;margin-bottom:16px;">' +
                '<button class="btn btn-primary btn-small" id="approve-mr">Approve</button>' +
                '</div>' +
                '<h3 style="margin-bottom:8px;">Discussions (' + discussions.length + ')</h3>' +
                discussionsHtml +
                '<h3 style="margin:16px 0 8px;">Add Comment</h3>' +
                '<textarea id="comment-body" rows="3" placeholder="Write a comment..."></textarea>' +
                '<button class="btn btn-primary btn-small" id="submit-comment" style="margin-top:8px;">Comment</button>' +
                '</div>';

            document.getElementById('back-to-mrs').addEventListener('click', fetchMRs);
            document.getElementById('approve-mr').addEventListener('click', async function () {
                try {
                    await api('/projects/' + projectId + '/merge_requests/' + iid + '/approve', { method: 'POST' });
                    showMRDetail(projectId, iid);
                } catch (e) { alert('Approve failed: ' + e.message); }
            });
            document.getElementById('submit-comment').addEventListener('click', async function () {
                var body = document.getElementById('comment-body').value.trim();
                if (!body) return;
                try {
                    await api('/projects/' + projectId + '/merge_requests/' + iid + '/discussions', {
                        method: 'POST',
                        body: JSON.stringify({ body: body })
                    });
                    showMRDetail(projectId, iid);
                } catch (e) { alert('Comment failed: ' + e.message); }
            });
        } catch (e) {
            container.innerHTML = '<div class="loading">Error: ' + escapeHtml(e.message) + '</div>';
        }
    }

    // Pipelines
    async function fetchPipelines() {
        var container = document.getElementById('pipelines');
        if (!GITLAB_PROJECT) {
            container.innerHTML = '<div class="loading">Set gitlab.project in cmux.json to view pipelines</div>';
            return;
        }
        try {
            var pipelines = await api('/projects/' + encodeProject() + '/pipelines?per_page=10');
            if (pipelines.length === 0) {
                container.innerHTML = '<div class="loading">No pipelines found</div>';
                return;
            }
            var top5 = pipelines.slice(0, 5);
            var pipelinesWithJobs = await Promise.all(
                top5.map(async function (p) {
                    var jobs = await api('/projects/' + encodeProject() + '/pipelines/' + p.id + '/jobs');
                    return Object.assign({}, p, { jobs: jobs });
                })
            );
            container.innerHTML = pipelinesWithJobs.map(function (p) {
                var retryBtn = p.status === 'failed'
                    ? ' <button class="btn btn-small btn-danger" onclick="retryPipeline(' + p.id + ')">Retry</button>'
                    : '';
                var jobsHtml = p.jobs.map(function (j) {
                    return '<span class="job-badge pipeline-status ' + j.status + '">' + escapeHtml(j.name) + '</span>';
                }).join('');
                return '<div class="pipeline-item">' +
                    '<div><span class="pipeline-status ' + p.status + '">' + p.status + '</span> ' +
                    '#' + p.id + ' &middot; ' + escapeHtml(p.ref) + ' &middot; ' + timeAgo(p.updated_at) + retryBtn + '</div>' +
                    '<div class="pipeline-jobs">' + jobsHtml + '</div></div>';
            }).join('');
        } catch (e) {
            container.innerHTML = '<div class="loading">Error: ' + escapeHtml(e.message) + '</div>';
        }
    }

    window.retryPipeline = async function (pipelineId) {
        try {
            await api('/projects/' + encodeProject() + '/pipelines/' + pipelineId + '/retry', { method: 'POST' });
            fetchPipelines();
        } catch (e) { alert('Retry failed: ' + e.message); }
    };

    // Create MR
    document.getElementById('create-mr-form').addEventListener('submit', async function (e) {
        e.preventDefault();
        if (!GITLAB_PROJECT) { alert('Set gitlab.project in cmux.json'); return; }
        var result = document.getElementById('create-mr-result');
        result.textContent = 'Creating...';
        try {
            var mr = await api('/projects/' + encodeProject() + '/merge_requests', {
                method: 'POST',
                body: JSON.stringify({
                    source_branch: document.getElementById('mr-source').value,
                    target_branch: document.getElementById('mr-target').value,
                    title: document.getElementById('mr-title').value,
                    description: document.getElementById('mr-description').value
                })
            });
            result.innerHTML = '<span style="color:var(--success);">Created !' + mr.iid + '</span>';
            document.getElementById('create-mr-form').reset();
        } catch (e) {
            result.innerHTML = '<span style="color:var(--danger);">' + escapeHtml(e.message) + '</span>';
        }
    });

    // Settings
    document.getElementById('settings-form').addEventListener('submit', function (e) {
        e.preventDefault();
        var host = document.getElementById('setting-host').value.trim().replace(/\/$/, '');
        var token = document.getElementById('setting-token').value.trim();
        if (!host || !token) { alert('Both fields required'); return; }
        GITLAB_HOST = host;
        GITLAB_TOKEN = token;
        window.__GITLAB_HOST__ = host;
        window.__GITLAB_TOKEN__ = token;
        document.getElementById('settings-result').innerHTML = '<span style="color:var(--success);">Saved (session only)</span>';
        fetchMRs();
        fetchPipelines();
        startPolling();
    });

    // Polling
    function startPolling() {
        if (pollTimer) clearInterval(pollTimer);
        pollTimer = setInterval(function () {
            fetchMRs();
            fetchPipelines();
        }, POLL_INTERVAL);
    }

    // Utilities
    function escapeHtml(s) {
        if (!s) return '';
        var div = document.createElement('div');
        div.textContent = s;
        return div.innerHTML;
    }

    function timeAgo(dateStr) {
        var diff = Date.now() - new Date(dateStr).getTime();
        var mins = Math.floor(diff / 60000);
        if (mins < 1) return 'just now';
        if (mins < 60) return mins + 'm ago';
        var hours = Math.floor(mins / 60);
        if (hours < 24) return hours + 'h ago';
        return Math.floor(hours / 24) + 'd ago';
    }

    if (window.__GITLAB_READY__) window.onGitLabReady();
})();
