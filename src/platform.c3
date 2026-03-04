module platform;

fn ZString get_surface_ext() @if ($feature(PLATFORM_WAYLAND))
{
	return "VK_KHR_wayland_surface";
}

fn ZString get_surface_ext() @if ($feature(PLATFORM_WIN32))
{
	return "VK_KHR_win32_surface";
}

fn ZString get_surface_ext() @if ($feature(PLATFORM_X11))
{
	return "VK_KHR_xcb_surface";
}
