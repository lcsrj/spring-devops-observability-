package br.com.devops.observability.service;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedDeque;
import java.util.concurrent.atomic.AtomicLong;

import org.springframework.stereotype.Service;

import br.com.devops.observability.model.ActionRecord;

/**
 * Historico em memoria das ultimas acoes executadas contra o backend.
 *
 * <p>Nao existe banco de dados na aplicacao (nao e requisito do projeto): o historico e um
 * buffer circular limitado, alimentado por um interceptor que mede a requisicao real.</p>
 */
@Service
public class ActionHistoryService {

    /** Quantidade maxima de acoes mantidas em memoria. */
    public static final int MAX_ENTRIES = 50;

    private final Deque<ActionRecord> history = new ConcurrentLinkedDeque<>();
    private final AtomicLong sequence = new AtomicLong();
    private final AtomicLong logEvents = new AtomicLong();
    private final OffsetDateTime startedAt = OffsetDateTime.now();

    public ActionRecord record(String action, String method, String endpoint,
                               int status, long durationMs, String correlationId) {
        ActionRecord entry = new ActionRecord(
                sequence.incrementAndGet(),
                OffsetDateTime.now().truncatedTo(ChronoUnit.MILLIS).toString(),
                action,
                method,
                endpoint,
                status,
                durationMs,
                correlationId);

        history.addFirst(entry);
        while (history.size() > MAX_ENTRIES) {
            history.pollLast();
        }
        return entry;
    }

    public void incrementLogEvents() {
        logEvents.incrementAndGet();
    }

    public List<ActionRecord> recent(int limit) {
        List<ActionRecord> snapshot = new ArrayList<>(history);
        if (snapshot.size() <= limit) {
            return Collections.unmodifiableList(snapshot);
        }
        return Collections.unmodifiableList(snapshot.subList(0, limit));
    }

    public ActionRecord lastAction() {
        return history.peekFirst();
    }

    public long totalRequests() {
        return sequence.get();
    }

    public long totalLogEvents() {
        return logEvents.get();
    }

    public OffsetDateTime startedAt() {
        return startedAt;
    }

    public void clear() {
        history.clear();
        sequence.set(0);
        logEvents.set(0);
    }

    /** Formata uma duracao como {@code 1d 02h 03m 04s}, omitindo unidades zeradas a esquerda. */
    public static String humanizeUptime(Duration uptime) {
        long days = uptime.toDays();
        long hours = uptime.toHoursPart();
        long minutes = uptime.toMinutesPart();
        long seconds = uptime.toSecondsPart();

        StringBuilder sb = new StringBuilder();
        if (days > 0) {
            sb.append(days).append("d ");
        }
        if (days > 0 || hours > 0) {
            sb.append(String.format("%02dh ", hours));
        }
        if (days > 0 || hours > 0 || minutes > 0) {
            sb.append(String.format("%02dm ", minutes));
        }
        sb.append(String.format("%02ds", seconds));
        return sb.toString().trim();
    }
}
