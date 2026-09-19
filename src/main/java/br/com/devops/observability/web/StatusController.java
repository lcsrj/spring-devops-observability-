package br.com.devops.observability.web;

import java.lang.management.ManagementFactory;
import java.time.Duration;
import java.time.temporal.ChronoUnit;
import java.util.List;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import br.com.devops.observability.config.AppProperties;
import br.com.devops.observability.model.ActionRecord;
import br.com.devops.observability.model.StatusResponse;
import br.com.devops.observability.service.ActionHistoryService;
import br.com.devops.observability.service.LogDemoService;

/** Estado da aplicacao e historico recente consumidos pelos cards da interface. */
@RestController
@RequestMapping("/api")
public class StatusController {

    private final AppProperties properties;
    private final ActionHistoryService history;
    private final LogDemoService logDemoService;

    public StatusController(AppProperties properties, ActionHistoryService history,
                            LogDemoService logDemoService) {
        this.properties = properties;
        this.history = history;
        this.logDemoService = logDemoService;
    }

    @GetMapping("/status")
    public StatusResponse status() {
        Duration uptime = Duration.ofMillis(ManagementFactory.getRuntimeMXBean().getUptime());
        var heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();

        return new StatusResponse(
                "UP",
                properties.getName(),
                properties.getVersion(),
                properties.getEnvironment(),
                hostname(),
                history.startedAt().truncatedTo(ChronoUnit.SECONDS).toString(),
                uptime.toSeconds(),
                ActionHistoryService.humanizeUptime(uptime),
                history.totalRequests(),
                history.totalLogEvents(),
                history.lastAction(),
                logDemoService.isGelfAppenderActive(),
                heap.getUsed(),
                heap.getMax(),
                ManagementFactory.getThreadMXBean().getThreadCount());
    }

    @GetMapping("/history")
    public List<ActionRecord> history(@RequestParam(defaultValue = "15") int limit) {
        int capped = Math.max(1, Math.min(limit, ActionHistoryService.MAX_ENTRIES));
        return history.recent(capped);
    }

    private String hostname() {
        try {
            return java.net.InetAddress.getLocalHost().getHostName();
        } catch (java.net.UnknownHostException ex) {
            return "desconhecido";
        }
    }
}
