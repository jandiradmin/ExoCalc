use std::{fs, path::PathBuf, sync::Mutex, time::Duration};

use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, WindowEvent,
};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};
use tauri_plugin_window_state::StateFlags;

/// Only these files may be read/written by the UI (in the app data folder).
const FILES: [&str; 4] = ["sheet.json", "history.json", "rates.json", "settings.json"];
/// Only these hosts may be fetched (exchange rates).
const HOSTS: [&str; 4] = [
    "https://open.er-api.com/",
    "https://bank.gov.ua/",
    "https://api.coingecko.com/",
    "https://api.coinbase.com/",
];

struct HotkeyState(Mutex<Option<Shortcut>>);

fn data_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let d = app.path().app_data_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&d).map_err(|e| e.to_string())?;
    Ok(d)
}

fn show(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
        let _ = app.emit("shown", ());
    }
}

fn toggle(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let visible = w.is_visible().unwrap_or(false);
        let focused = w.is_focused().unwrap_or(false);
        let minimized = w.is_minimized().unwrap_or(false);
        if visible && focused && !minimized {
            let _ = w.hide();
        } else {
            show(app);
        }
    }
}

fn build_menu(app: &AppHandle, labels: &[String]) -> tauri::Result<Menu<tauri::Wry>> {
    let label = |i: usize, default: &str| labels.get(i).cloned().unwrap_or_else(|| default.to_string());
    let show_item = MenuItem::with_id(app, "show", label(0, "Show / Hide"), true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", label(1, "Settings…"), true, None::<&str>)?;
    let sep = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", label(2, "Quit"), true, None::<&str>)?;
    Menu::with_items(app, &[&show_item, &settings, &sep, &quit])
}

#[tauri::command]
fn load_file(app: AppHandle, name: String) -> Option<String> {
    if !FILES.contains(&name.as_str()) {
        return None;
    }
    fs::read_to_string(data_dir(&app).ok()?.join(name)).ok()
}

#[tauri::command]
fn save_file(app: AppHandle, name: String, content: String) -> Result<(), String> {
    if !FILES.contains(&name.as_str()) {
        return Err("file not allowed".into());
    }
    let dir = data_dir(&app)?;
    let tmp = dir.join(format!("{name}.tmp"));
    fs::write(&tmp, content).map_err(|e| e.to_string())?;
    fs::rename(&tmp, dir.join(&name)).map_err(|e| e.to_string())
}

#[tauri::command]
async fn fetch_json(url: String) -> Result<String, String> {
    if !HOSTS.iter().any(|h| url.starts_with(h)) {
        return Err("host not allowed".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        ureq::get(&url)
            .set("User-Agent", "ExoCalc/1.2")
            .timeout(Duration::from_secs(15))
            .call()
            .map_err(|e| e.to_string())?
            .into_string()
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[derive(serde::Serialize)]
struct UpdateInfo {
    version: String,
    notes: Option<String>,
}

#[tauri::command]
fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

/// Newer version on GitHub Releases (signed latest.json), if any.
#[tauri::command]
async fn check_update(app: AppHandle) -> Result<Option<UpdateInfo>, String> {
    use tauri_plugin_updater::UpdaterExt;
    let update = app.updater().map_err(|e| e.to_string())?.check().await.map_err(|e| e.to_string())?;
    Ok(update.map(|u| UpdateInfo { version: u.version.clone(), notes: u.body.clone() }))
}

/// Downloads, verifies the signature, installs and restarts.
#[tauri::command]
async fn install_update(app: AppHandle) -> Result<(), String> {
    use tauri_plugin_updater::UpdaterExt;
    let update = app.updater().map_err(|e| e.to_string())?.check().await.map_err(|e| e.to_string())?;
    let Some(update) = update else { return Err("no update".into()) };
    update.download_and_install(|_, _| {}, || {}).await.map_err(|e| e.to_string())?;
    app.restart()
}

#[tauri::command]
fn hide_window(app: AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.hide();
    }
}

#[tauri::command]
fn set_hotkey(app: AppHandle, state: tauri::State<'_, HotkeyState>, accel: String) -> Result<(), String> {
    let sc: Shortcut = accel.parse().map_err(|e| format!("{e:?}"))?;
    let gs = app.global_shortcut();
    let mut current = state.0.lock().map_err(|e| e.to_string())?;
    if let Some(old) = current.take() {
        let _ = gs.unregister(old);
    }
    gs.register(sc.clone()).map_err(|e| e.to_string())?;
    *current = Some(sc);
    Ok(())
}

#[tauri::command]
fn set_always_on_top(app: AppHandle, on: bool) -> Result<(), String> {
    if let Some(w) = app.get_webview_window("main") {
        w.set_always_on_top(on).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn set_autostart(app: AppHandle, on: bool) -> Result<(), String> {
    let al = app.autolaunch();
    let r = if on { al.enable() } else { al.disable() };
    r.map_err(|e| e.to_string())
}

#[tauri::command]
fn get_autostart(app: AppHandle) -> bool {
    app.autolaunch().is_enabled().unwrap_or(false)
}

#[tauri::command]
fn set_tray_labels(app: AppHandle, labels: Vec<String>) -> Result<(), String> {
    let menu = build_menu(&app, &labels).map_err(|e| e.to_string())?;
    if let Some(t) = app.tray_by_id("main") {
        t.set_menu(Some(menu)).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| show(app)))
        .plugin(
            tauri_plugin_window_state::Builder::default()
                .with_state_flags(StateFlags::all() & !StateFlags::VISIBLE)
                .build(),
        )
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, Some(vec!["--hidden"])))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _shortcut, event| {
                    if event.state() == ShortcutState::Pressed {
                        toggle(app);
                    }
                })
                .build(),
        )
        .manage(HotkeyState(Mutex::new(None)))
        .invoke_handler(tauri::generate_handler![
            load_file,
            save_file,
            fetch_json,
            hide_window,
            app_version,
            check_update,
            install_update,
            set_hotkey,
            set_always_on_top,
            set_autostart,
            get_autostart,
            set_tray_labels
        ])
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .setup(|app| {
            let handle = app.handle().clone();
            let menu = build_menu(&handle, &[])?;
            let mut tray = TrayIconBuilder::with_id("main")
                .tooltip("ExoCalc")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        toggle(tray.app_handle());
                    }
                })
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "show" => toggle(app),
                    "settings" => {
                        show(app);
                        let _ = app.emit("open-settings", ());
                    }
                    "quit" => app.exit(0),
                    _ => {}
                });
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            tray.build(app)?;

            if !std::env::args().any(|a| a == "--hidden") {
                show(&handle);
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running ExoCalc");
}
