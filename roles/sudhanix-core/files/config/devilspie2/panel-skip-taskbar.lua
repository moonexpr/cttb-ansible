-- Hide xfce4-panel wrapper windows from Plank dock / taskbar
-- These wrappers host panel plugins and incorrectly appear as normal windows
if get_application_name() == "xfce4-panel" or
   get_window_name() == "xfce4-panel" or
   string.find(get_process_name() or "", "wrapper") then
    set_skip_tasklist(true)
    set_skip_pager(true)
end
