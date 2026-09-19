/* ===========================================================================
 * DevOps Observability Control Center - frontend
 *
 * JavaScript puro, sem dependencias externas e sem CDN. Todas as acoes abaixo
 * disparam requisicoes HTTP reais contra o backend Spring Boot; nada e simulado
 * no navegador. O painel apenas exibe o que o servidor respondeu.
 * =========================================================================== */
(function () {
    'use strict';

    var STATUS_POLL_MS = 10000;
    var HISTORY_LIMIT = 15;

    var el = {
        status: document.getElementById('card-status'),
        statusDot: document.getElementById('status-dot'),
        host: document.getElementById('card-host'),
        uptime: document.getElementById('card-uptime'),
        started: document.getElementById('card-started'),
        requests: document.getElementById('card-requests'),
        logEvents: document.getElementById('card-logevents'),
        lastAction: document.getElementById('card-last-action'),
        lastActionMeta: document.getElementById('card-last-action-meta'),
        version: document.getElementById('card-version'),
        environment: document.getElementById('card-environment'),
        jvm: document.getElementById('card-jvm'),
        historyBody: document.getElementById('history-body'),
        burstCount: document.getElementById('burst-count'),
        burstResult: document.getElementById('burst-result'),
        gelfDot: document.getElementById('gelf-dot'),
        gelfText: document.getElementById('gelf-state-text'),
        toasts: document.getElementById('toasts')
    };

    var lastSequenceSeen = 0;

    /* ----------------------------- utilitarios ----------------------------- */

    function formatBytes(bytes) {
        if (typeof bytes !== 'number' || bytes < 0) {
            return '--';
        }
        var units = ['B', 'KB', 'MB', 'GB'];
        var value = bytes;
        var unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value = value / 1024;
            unit++;
        }
        return value.toFixed(value >= 100 || unit === 0 ? 0 : 1) + ' ' + units[unit];
    }

    function formatClock(isoString) {
        if (!isoString) {
            return '--';
        }
        var date = new Date(isoString);
        if (isNaN(date.getTime())) {
            return isoString;
        }
        return date.toLocaleTimeString('pt-BR', { hour12: false });
    }

    function formatDateTime(isoString) {
        if (!isoString) {
            return '--';
        }
        var date = new Date(isoString);
        if (isNaN(date.getTime())) {
            return isoString;
        }
        return date.toLocaleString('pt-BR', { hour12: false });
    }

    function statusClass(status) {
        if (status >= 200 && status < 300) {
            return 'pill--2xx';
        }
        if (status >= 400 && status < 500) {
            return 'pill--4xx';
        }
        if (status >= 500) {
            return 'pill--5xx';
        }
        return 'pill--other';
    }

    function toastKindFor(status) {
        if (status >= 200 && status < 300) {
            return 'success';
        }
        if (status >= 400 && status < 500) {
            return 'warning';
        }
        if (status >= 500) {
            return 'error';
        }
        return 'info';
    }

    function toast(kind, title, detail) {
        if (!el.toasts) {
            return;
        }
        var node = document.createElement('div');
        node.className = 'toast toast--' + kind;

        var body = document.createElement('div');
        body.className = 'toast__body';

        var titleNode = document.createElement('div');
        titleNode.className = 'toast__title';
        titleNode.textContent = title;
        body.appendChild(titleNode);

        if (detail) {
            var detailNode = document.createElement('div');
            detailNode.className = 'toast__detail';
            detailNode.textContent = detail;
            body.appendChild(detailNode);
        }

        node.appendChild(body);
        el.toasts.appendChild(node);

        window.setTimeout(function () {
            node.classList.add('is-leaving');
            window.setTimeout(function () {
                if (node.parentNode) {
                    node.parentNode.removeChild(node);
                }
            }, 220);
        }, 4600);
    }

    function setLoading(button, loading) {
        if (!button) {
            return;
        }
        button.disabled = loading;
        button.classList.toggle('is-loading', loading);
        button.setAttribute('aria-busy', loading ? 'true' : 'false');
    }

    /* -------------------------- chamadas ao backend ------------------------ */

    /**
     * Executa a requisicao e devolve sempre status + corpo, inclusive em 4xx/5xx:
     * erros HTTP sao resultados esperados neste painel, nao excecoes.
     */
    function callBackend(endpoint, method, payload) {
        var options = {
            method: method,
            headers: { 'Accept': 'application/json' }
        };
        if (payload !== undefined && payload !== null) {
            options.headers['Content-Type'] = 'application/json';
            options.body = JSON.stringify(payload);
        }

        var started = performance.now();
        return fetch(endpoint, options).then(function (response) {
            var elapsed = Math.round(performance.now() - started);
            return response.text().then(function (text) {
                var body = null;
                if (text) {
                    try {
                        body = JSON.parse(text);
                    } catch (e) {
                        body = { raw: text };
                    }
                }
                return {
                    status: response.status,
                    correlationId: response.headers.get('X-Correlation-Id'),
                    elapsedMs: elapsed,
                    body: body
                };
            });
        });
    }

    /* ---------------------------- cards de estado -------------------------- */

    function renderStatus(data) {
        el.status.textContent = data.status || '--';
        el.statusDot.className = 'dot ' + (data.status === 'UP' ? 'dot--up' : 'dot--down');
        el.host.textContent = 'host: ' + (data.hostname || '--');

        el.uptime.textContent = data.uptimeHuman || '--';
        el.started.textContent = 'iniciada em ' + formatDateTime(data.startedAt);

        el.requests.textContent = String(data.totalRequests);
        el.logEvents.textContent = data.totalLogEvents + ' eventos de log gerados';

        if (data.lastAction) {
            el.lastAction.textContent = data.lastAction.action;
            el.lastActionMeta.textContent = data.lastAction.method + ' ' + data.lastAction.endpoint +
                ' -> ' + data.lastAction.status + ' (' + data.lastAction.durationMs + ' ms) as ' +
                formatClock(data.lastAction.timestamp);
        } else {
            el.lastAction.textContent = 'nenhuma acao ainda';
            el.lastActionMeta.textContent = 'aguardando a primeira interacao';
        }

        updateGelfState(data.logShippingActive);

        el.version.textContent = data.version;
        el.environment.textContent = String(data.environment || '').toUpperCase();
        el.jvm.textContent = 'heap ' + formatBytes(data.heapUsedBytes) + ' / ' +
            formatBytes(data.heapMaxBytes) + ' - ' + data.liveThreads + ' threads';
    }

    function renderHistory(entries) {
        if (!entries || entries.length === 0) {
            el.historyBody.innerHTML =
                '<tr class="table__empty"><td colspan="7">' +
                'Nenhuma acao registrada ainda. Use os botoes acima para gerar trafego ou logs.' +
                '</td></tr>';
            return;
        }

        var highestSequence = lastSequenceSeen;
        var fragment = document.createDocumentFragment();

        entries.forEach(function (entry) {
            var row = document.createElement('tr');
            if (entry.sequence > lastSequenceSeen) {
                row.className = 'row-new';
            }
            if (entry.sequence > highestSequence) {
                highestSequence = entry.sequence;
            }

            appendCell(row, String(entry.sequence), 'muted');
            appendCell(row, formatClock(entry.timestamp), 'mono');
            appendCell(row, entry.action, '');
            appendCell(row, entry.method + ' ' + entry.endpoint, 'mono');

            var statusCell = document.createElement('td');
            var pill = document.createElement('span');
            pill.className = 'pill ' + statusClass(entry.status);
            pill.textContent = String(entry.status);
            statusCell.appendChild(pill);
            row.appendChild(statusCell);

            appendCell(row, entry.durationMs + ' ms', 'mono');
            appendCell(row, entry.correlationId, 'muted');

            fragment.appendChild(row);
        });

        el.historyBody.innerHTML = '';
        el.historyBody.appendChild(fragment);
        lastSequenceSeen = highestSequence;
    }

    function appendCell(row, text, className) {
        var cell = document.createElement('td');
        if (className) {
            cell.className = className;
        }
        cell.textContent = text;
        row.appendChild(cell);
    }

    function refresh(showErrors) {
        return Promise.all([
            fetch('/api/status', { headers: { 'Accept': 'application/json' } }).then(function (r) {
                return r.json();
            }),
            fetch('/api/history?limit=' + HISTORY_LIMIT, { headers: { 'Accept': 'application/json' } })
                .then(function (r) {
                    return r.json();
                })
        ]).then(function (results) {
            renderStatus(results[0]);
            renderHistory(results[1]);
        }).catch(function (error) {
            el.statusDot.className = 'dot dot--down';
            el.status.textContent = 'INDISPONIVEL';
            if (showErrors) {
                toast('error', 'Nao foi possivel consultar o backend', String(error.message || error));
            }
        });
    }

    /* ------------------------------- acoes --------------------------------- */

    function handleSingleCall(button) {
        var endpoint = button.getAttribute('data-endpoint');
        var method = button.getAttribute('data-method') || 'GET';
        var label = button.getAttribute('data-label') || endpoint;

        setLoading(button, true);
        callBackend(endpoint, method).then(function (result) {
            var detail = method + ' ' + endpoint + ' -> HTTP ' + result.status +
                ' em ' + result.elapsedMs + ' ms';
            toast(toastKindFor(result.status), label + ' executado', detail);
            return refresh(false);
        }).catch(function (error) {
            toast('error', 'Falha de rede em ' + label, String(error.message || error));
        }).then(function () {
            setLoading(button, false);
        });
    }

    function handleLogCall(button) {
        var endpoint = button.getAttribute('data-endpoint');
        var label = button.getAttribute('data-label') || endpoint;

        setLoading(button, true);
        callBackend(endpoint, 'POST', {}).then(function (result) {
            var body = result.body || {};
            if (result.status >= 200 && result.status < 300) {
                updateGelfState(body.sentToGraylog);
                toast('success', label + ' emitido no backend',
                    'nivel ' + body.level + ' - correlation ' + (body.correlationId || '--'));
            } else {
                toast(toastKindFor(result.status), 'Falha ao emitir ' + label, 'HTTP ' + result.status);
            }
            return refresh(false);
        }).catch(function (error) {
            toast('error', 'Falha de rede em ' + label, String(error.message || error));
        }).then(function () {
            setLoading(button, false);
        });
    }

    function updateGelfState(sentToGraylog) {
        if (!el.gelfDot || !el.gelfText) {
            return;
        }
        if (sentToGraylog === true) {
            el.gelfDot.className = 'dot dot--up';
            el.gelfText.textContent = 'Envio ao Graylog: appender GELF ativo (UDP 12201)';
        } else if (sentToGraylog === false) {
            el.gelfDot.className = 'dot dot--down';
            el.gelfText.textContent =
                'Envio ao Graylog: appender GELF inativo - execucao fora do perfil docker, log apenas no console';
        }
    }

    function handleBurst(button) {
        var requested = parseInt(el.burstCount.value, 10);
        if (isNaN(requested) || requested < 1) {
            toast('warning', 'Quantidade invalida', 'informe um numero entre 1 e 200');
            el.burstCount.focus();
            return;
        }
        if (requested > 200) {
            requested = 200;
            el.burstCount.value = '200';
            toast('info', 'Quantidade ajustada para o limite', 'maximo de 200 requisicoes por rajada');
        }

        setLoading(button, true);
        el.burstResult.hidden = true;

        callBackend('/api/demo/traffic', 'POST', { requests: requested }).then(function (result) {
            if (result.status >= 200 && result.status < 300 && result.body) {
                renderBurstResult(result.body);
                toast('success', 'Rajada concluida',
                    result.body.executed + ' requisicoes reais em ' + result.body.durationMs + ' ms');
            } else {
                toast(toastKindFor(result.status), 'Falha ao gerar rajada', 'HTTP ' + result.status);
            }
            return refresh(false);
        }).catch(function (error) {
            toast('error', 'Falha de rede na rajada', String(error.message || error));
        }).then(function () {
            setLoading(button, false);
        });
    }

    function renderBurstResult(result) {
        el.burstResult.innerHTML = '';
        var items = [
            ['executadas', result.executed],
            ['2xx', result.success2xx],
            ['4xx', result.clientError4xx],
            ['5xx', result.serverError5xx],
            ['falhas', result.failures],
            ['duracao', result.durationMs + ' ms']
        ];
        items.forEach(function (item) {
            var span = document.createElement('span');
            var strong = document.createElement('strong');
            strong.textContent = String(item[1]);
            span.appendChild(document.createTextNode(item[0] + ': '));
            span.appendChild(strong);
            el.burstResult.appendChild(span);
        });
        el.burstResult.hidden = false;
    }

    /* ------------------------------- bootstrap ----------------------------- */

    document.addEventListener('click', function (event) {
        var button = event.target.closest('button[data-action]');
        if (!button || button.disabled) {
            return;
        }

        switch (button.getAttribute('data-action')) {
            case 'call':
                handleSingleCall(button);
                break;
            case 'log':
                handleLogCall(button);
                break;
            case 'burst':
                handleBurst(button);
                break;
            case 'refresh':
                setLoading(button, true);
                refresh(true).then(function () {
                    setLoading(button, false);
                    toast('info', 'Estado atualizado', 'dados relidos de /api/status e /api/history');
                });
                break;
            default:
                break;
        }
    });

    el.burstCount.addEventListener('keydown', function (event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            var button = document.querySelector('button[data-action="burst"]');
            if (button && !button.disabled) {
                handleBurst(button);
            }
        }
    });

    refresh(true);
    window.setInterval(function () {
        refresh(false);
    }, STATUS_POLL_MS);
})();
