package br.com.devops.observability.web;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import br.com.devops.observability.config.AppProperties;

/** Serve o painel Thymeleaf em {@code GET /}. */
@Controller
public class HomeController {

    private final AppProperties properties;

    public HomeController(AppProperties properties) {
        this.properties = properties;
    }

    @GetMapping("/")
    public String index(Model model) {
        model.addAttribute("app", properties);
        return "index";
    }
}
