#include <gtk/gtk.h>
#include <string.h>

static const char *UNIT = "p2app.service";

static gboolean run_capture(const char *cmd, char *out, gsize outlen) {
    gchar *stdout_buf = NULL, *stderr_buf = NULL;
    gint status = 0;
    GError *err = NULL;

    gboolean ok = g_spawn_command_line_sync(cmd, &stdout_buf, &stderr_buf, &status, &err);

    if (!ok || err) {
        if (out && outlen) g_strlcpy(out, err ? err->message : "spawn failed", outlen);
        if (err) g_error_free(err);
        g_free(stdout_buf);
        g_free(stderr_buf);
        return FALSE;
    }

    if (out && outlen) {
        // Prefer stdout; fall back to stderr if stdout is empty.
        const char *src = (stdout_buf && *stdout_buf) ? stdout_buf : (stderr_buf ? stderr_buf : "");
        g_strlcpy(out, src, outlen);
    }

    g_free(stdout_buf);
    g_free(stderr_buf);
    return TRUE;
}

static gboolean is_active(void) {
    char buf[128] = {0};
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "systemctl is-active %s", UNIT);
    if (!run_capture(cmd, buf, sizeof(buf))) return FALSE;
    g_strstrip(buf);
    return strcmp(buf, "active") == 0;
}

static void pkexec_systemctl(const char *verb) {
    // pkexec will use polkit; may prompt in GUI if not authorized.
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "pkexec /bin/systemctl %s %s", verb, UNIT);
    (void)system(cmd);
}

typedef struct {
    GtkWidget *label;
    GtkWidget *btn_start;
    GtkWidget *btn_stop;
    GtkWidget *btn_restart;
} UI;

static void on_start(GtkButton *b, gpointer data)  { (void)b; (void)data; pkexec_systemctl("start"); }
static void on_stop(GtkButton *b, gpointer data)   { (void)b; (void)data; pkexec_systemctl("stop"); }
static void on_restart(GtkButton *b, gpointer data){ (void)b; (void)data; pkexec_systemctl("restart"); }

static gboolean refresh(gpointer data) {
    UI *ui = (UI*)data;
    gboolean active = is_active();

    gtk_label_set_text(GTK_LABEL(ui->label), active ? "P2_app: RUNNING" : "P2_app: STOPPED");
    gtk_widget_set_sensitive(ui->btn_start, !active);
    gtk_widget_set_sensitive(ui->btn_stop,  active);
    gtk_widget_set_sensitive(ui->btn_restart, TRUE);

    return TRUE;
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "P2_app Control");
    gtk_window_set_resizable(GTK_WINDOW(win), FALSE);
    gtk_container_set_border_width(GTK_CONTAINER(win), 10);

    // Wayland/labwc may ignore this hint; harmless.
    gtk_window_set_keep_above(GTK_WINDOW(win), TRUE);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    UI ui = {0};

    ui.label = gtk_label_new("P2_app: …");
    gtk_box_pack_start(GTK_BOX(vbox), ui.label, FALSE, FALSE, 0);

    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_box_pack_start(GTK_BOX(vbox), hbox, FALSE, FALSE, 0);

    ui.btn_start = gtk_button_new_with_label("Start");
    ui.btn_stop  = gtk_button_new_with_label("Stop");
    ui.btn_restart = gtk_button_new_with_label("Restart");

    gtk_box_pack_start(GTK_BOX(hbox), ui.btn_start, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), ui.btn_stop, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), ui.btn_restart, TRUE, TRUE, 0);

    g_signal_connect(ui.btn_start, "clicked", G_CALLBACK(on_start), &ui);
    g_signal_connect(ui.btn_stop, "clicked", G_CALLBACK(on_stop), &ui);
    g_signal_connect(ui.btn_restart, "clicked", G_CALLBACK(on_restart), &ui);

    GtkWidget *btn_quit = gtk_button_new_with_label("Quit");
    gtk_box_pack_start(GTK_BOX(vbox), btn_quit, FALSE, FALSE, 0);
    g_signal_connect(btn_quit, "clicked", G_CALLBACK(gtk_main_quit), NULL);

    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    gtk_widget_show_all(win);

    g_timeout_add(500, refresh, &ui);
    refresh(&ui);

    gtk_main();
    return 0;
}
