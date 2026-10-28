/* Taken from https://github.com/djpohly/dwl/issues/466 */
#define COLOR(hex)    { ((hex >> 24) & 0xFF) / 255.0f, \
                        ((hex >> 16) & 0xFF) / 255.0f, \
                        ((hex >> 8) & 0xFF) / 255.0f, \
                        (hex & 0xFF) / 255.0f }
/* appearance */
static const int sloppyfocus               = 1;  /* focus follows mouse */
static const int bypass_surface_visibility = 0;  /* 1 means idle inhibitors will disable idle tracking even if it's surface isn't visible  */
static const unsigned int borderpx         = 1;  /* border pixel of windows */
static const unsigned int snap             = 32; /* snap pixel */
static const int showbar                   = 1; /* 0 means no bar */
static const int topbar                    = 1; /* 0 means bottom bar */
static const char *fonts[]                 = {"DejaVu Sans Mono:size=10"};
static const float rootcolor[]             = COLOR(0x000000ff);
/* This conforms to the xdg-protocol. Set the alpha to zero to restore the old behavior */
static const float fullscreen_bg[]         = {0.0f, 0.0f, 0.0f, 1.0f}; /* You can also use glsl colors */
static uint32_t colors[][3]                = {
	/*               fg          bg          border    */
	[SchemeNorm] = { 0xbbbbbbff, 0x222222ff, 0x444444ff },
	[SchemeSel]  = { 0xeeeeeeff, 0x005577ff, 0x005577ff },
	[SchemeUrg]  = { 0,          0,          0x770000ff },
	[SchemeOcc]  = { 0xeeeeeeff, 0x222222ff, 0x444444ff }, /* tags with windows */
	[SchemeEmpty]= { 0x777777ff, 0x222222ff, 0x444444ff }, /* empty tags */
};

/* status text colours, selected by the bytes \x01, \x02, ... in the status */
static uint32_t statuscolors[][3]          = {
	/*  fg          bg          border */
	{ 0x999999ff, 0x222222ff, 0 }, /* \x01 brackets and labels */
	{ 0xeeeeeeff, 0x222222ff, 0 }, /* \x02 values */
	{ 0x33a6d9ff, 0x222222ff, 0 }, /* \x03 now playing */
};

/* tagging */
static char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

/* logging */
static int log_level = WLR_ERROR;

static const Rule rules[] = {
	/* app_id             title       tags mask     isfloating   monitor */
	{ "Gimp_EXAMPLE",     NULL,       0,            1,           -1 }, /* Start on currently visible tags floating, not tiled */
	{ "firefox_EXAMPLE",  NULL,       1 << 8,       0,           -1 }, /* Start on ONLY tag "9" */
    /* default/example rule: can be changed but cannot be eliminated; at least one rule must exist */
};

/* layout(s) */
static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "[]=",      tile },
	{ "><>",      NULL },    /* no layout function means floating behavior */
	{ "[M]",      monocle },
};

/* monitors */
/* (x=-1, y=-1) is reserved as an "autoconfigure" monitor position indicator
 * WARNING: negative values other than (-1, -1) cause problems with Xwayland clients due to
 * https://gitlab.freedesktop.org/xorg/xserver/-/issues/899 */
static const MonitorRule monrules[] = {
   /* name        mfact  nmaster scale  layout       rotate/reflect                x    y    width height refresh
    * example of a HiDPI laptop monitor:
    { "eDP-1",    0.5f,  1,      2,     &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL,   -1,  -1,  0,    0,     0 }, */
	{ NULL,       0.55f, 1,      1.25f, &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL,   -1,  -1,  3840, 2160,  240 },
	/* default monitor rule: can be changed but cannot be eliminated; at least one monitor rule must exist */
};

/* keyboard */
static const struct xkb_rule_names xkb_rules = {
	/* can specify fields: rules, model, layout, variant, options */
	/* example:
	.options = "ctrl:nocaps",
	*/
	.layout = "hu",
	.options = NULL,
};

static const int repeat_rate = 25;
static const int repeat_delay = 600;

/* Trackpad */
static const int tap_to_click = 1;
static const int tap_and_drag = 1;
static const int drag_lock = 1;
static const int natural_scrolling = 0;
static const int disable_while_typing = 1;
static const int left_handed = 0;
static const int middle_button_emulation = 0;
/* You can choose between:
LIBINPUT_CONFIG_SCROLL_NO_SCROLL
LIBINPUT_CONFIG_SCROLL_2FG
LIBINPUT_CONFIG_SCROLL_EDGE
LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN
*/
static const enum libinput_config_scroll_method scroll_method = LIBINPUT_CONFIG_SCROLL_2FG;

/* You can choose between:
LIBINPUT_CONFIG_CLICK_METHOD_NONE
LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS
LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER
*/
static const enum libinput_config_click_method click_method = LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS;

/* You can choose between:
LIBINPUT_CONFIG_SEND_EVENTS_ENABLED
LIBINPUT_CONFIG_SEND_EVENTS_DISABLED
LIBINPUT_CONFIG_SEND_EVENTS_DISABLED_ON_EXTERNAL_MOUSE
*/
static const uint32_t send_events_mode = LIBINPUT_CONFIG_SEND_EVENTS_ENABLED;

/* You can choose between:
LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT
LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE
*/
static const enum libinput_config_accel_profile accel_profile = LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;
static const double accel_speed = 0.0;

/* You can choose between:
LIBINPUT_CONFIG_TAP_MAP_LRM -- 1/2/3 finger tap maps to left/right/middle
LIBINPUT_CONFIG_TAP_MAP_LMR -- 1/2/3 finger tap maps to left/middle/right
*/
static const enum libinput_config_tap_button_map button_map = LIBINPUT_CONFIG_TAP_MAP_LRM;

/* If you want to use the windows key for MODKEY, use WLR_MODIFIER_LOGO */
#define MODKEY WLR_MODIFIER_LOGO

#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                    KEY,            view,            {.ui = 1 << TAG} }, \
	{ MODKEY|WLR_MODIFIER_CTRL,  KEY,            toggleview,      {.ui = 1 << TAG} }, \
	{ MODKEY|WLR_MODIFIER_SHIFT, KEY,            tag,             {.ui = 1 << TAG} }, \
	{ MODKEY|WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT,KEY,toggletag,  {.ui = 1 << TAG} }

/* helper for spawning shell commands in the pre dwm-5.0 fashion */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

#define RUMDA "~/.config/rumda/scripts/"

/* commands */
static const char *termcmd[] = { "kitty", NULL };
static const char *filecmd[] = { "thunar", NULL };
static const char *menucmd[] = { "rofi", "-show", "drun", NULL };

/* view the next/previous tag that has windows on it */
static void
shiftview(const Arg *arg)
{
	Client *c;
	uint32_t occ = 0, cur = selmon->tagset[selmon->seltags];
	int i, n = LENGTH(tags);
	Arg a;

	wl_list_for_each(c, &clients, link)
		if (c->mon == selmon)
			occ |= c->tags;
	for (i = 1; i < n; i++) {
		a.ui = (arg->i > 0 ? cur << i | cur >> (n - i) : cur >> i | cur << (n - i)) & TAGMASK;
		if (a.ui & occ) {
			view(&a);
			return;
		}
	}
}

/* toggle floating; a window that starts floating is sized to 60%x65% and centred */
static void
togglefloatcenter(const Arg *arg)
{
	Client *c = focustop(selmon);

	if (!c || c->isfullscreen)
		return;
	setfloating(c, !c->isfloating);
	if (c->isfloating)
		resize(c, (struct wlr_box){
			.x = selmon->w.x + selmon->w.width * 20 / 100,
			.y = selmon->w.y + selmon->w.height * 35 / 200,
			.width = selmon->w.width * 60 / 100,
			.height = selmon->w.height * 65 / 100 }, 0);
}

static const Key keys[] = {
	/* modifier                  key                  function          argument */
	{ MODKEY,                    XKB_KEY_Return,      spawn,            {.v = termcmd} },
	{ MODKEY,                    XKB_KEY_q,           killclient,       {0} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_x,           quit,             {0} },
	{ MODKEY,                    XKB_KEY_e,           spawn,            {.v = filecmd} },
	{ MODKEY,                    XKB_KEY_u,           togglefloating,   {0} },
	{ MODKEY,                    XKB_KEY_f,           togglefullscreen, {0} },
	{ MODKEY,                    XKB_KEY_d,           spawn,            {.v = menucmd} },
	{ MODKEY,                    XKB_KEY_j,           zoom,             {0} },
	{ MODKEY,                    XKB_KEY_Left,        focusstack,       {.i = -1} },
	{ MODKEY,                    XKB_KEY_Up,          focusstack,       {.i = -1} },
	{ MODKEY,                    XKB_KEY_Right,       focusstack,       {.i = +1} },
	{ MODKEY,                    XKB_KEY_Down,        focusstack,       {.i = +1} },
	{ MODKEY,                    XKB_KEY_h,           setmfact,         {.f = -0.05f} },
	{ MODKEY,                    XKB_KEY_l,           setmfact,         {.f = +0.05f} },
	{ MODKEY,                    XKB_KEY_space,       setlayout,        {0} },
	{ MODKEY,                    XKB_KEY_b,           togglebar,        {0} },
	{ MODKEY,                    XKB_KEY_Tab,         view,             {0} },
	{ MODKEY,                    XKB_KEY_0,           view,             {.ui = ~0} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_0,           tag,              {.ui = ~0} },
	{ MODKEY,                    XKB_KEY_comma,       focusmon,         {.i = WLR_DIRECTION_LEFT} },
	{ MODKEY,                    XKB_KEY_period,      focusmon,         {.i = WLR_DIRECTION_RIGHT} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_comma,       tagmon,           {.i = WLR_DIRECTION_LEFT} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_period,      tagmon,           {.i = WLR_DIRECTION_RIGHT} },
	TAGKEYS(                     XKB_KEY_1,           0),
	TAGKEYS(                     XKB_KEY_2,           1),
	TAGKEYS(                     XKB_KEY_3,           2),
	TAGKEYS(                     XKB_KEY_4,           3),
	TAGKEYS(                     XKB_KEY_5,           4),
	TAGKEYS(                     XKB_KEY_6,           5),
	TAGKEYS(                     XKB_KEY_7,           6),
	TAGKEYS(                     XKB_KEY_8,           7),
	TAGKEYS(                     XKB_KEY_9,           8),

	/* rumda scripts */
	{ MODKEY,                    XKB_KEY_w,           spawn,            SHCMD(RUMDA "wallcycle.sh") },
	{ 0,                         XKB_KEY_Print,       spawn,            SHCMD(RUMDA "qscreen.sh") },
	{ MODKEY,                    XKB_KEY_Print,       spawn,            SHCMD(RUMDA "screenshot.sh") },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_t,           spawn,            SHCMD(RUMDA "ocr.sh") },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_r,           spawn,            SHCMD(RUMDA "screenrec.sh") },
	{ MODKEY|WLR_MODIFIER_ALT,   XKB_KEY_r,           spawn,            SHCMD(RUMDA "screenrec.sh region") },

	/* multimedia keys */
	{ 0, XKB_KEY_XF86AudioRaiseVolume,  spawn, SHCMD("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+") },
	{ 0, XKB_KEY_XF86AudioLowerVolume,  spawn, SHCMD("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") },
	{ 0, XKB_KEY_XF86AudioMute,         spawn, SHCMD("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") },
	{ 0, XKB_KEY_XF86AudioMicMute,      spawn, SHCMD("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle") },
	{ 0, XKB_KEY_XF86MonBrightnessUp,   spawn, SHCMD("brightnessctl -e4 -n2 set 5%+") },
	{ 0, XKB_KEY_XF86MonBrightnessDown, spawn, SHCMD("brightnessctl -e4 -n2 set 5%-") },
	{ 0, XKB_KEY_XF86AudioNext,         spawn, SHCMD("playerctl next") },
	{ 0, XKB_KEY_XF86AudioPause,        spawn, SHCMD("playerctl play-pause") },
	{ 0, XKB_KEY_XF86AudioPlay,         spawn, SHCMD("playerctl play-pause") },
	{ 0, XKB_KEY_XF86AudioPrev,         spawn, SHCMD("playerctl previous") },

	/* Ctrl-Alt-Backspace and Ctrl-Alt-Fx used to be handled by X server */
	{ WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT,XKB_KEY_BackSpace, quit, {0} },
	/* Ctrl-Alt-Fx is used to switch to another VT, if you don't know what a VT is
	 * do not remove them.
	 */
#define CHVT(n) { WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT,XKB_KEY_F##n, chvt, {.ui = (n)} }
	CHVT(1), CHVT(2), CHVT(3), CHVT(4), CHVT(5), CHVT(6),
	CHVT(7), CHVT(8), CHVT(9), CHVT(10), CHVT(11), CHVT(12),
};

static const Button buttons[] = {
	{ ClkStatus,   0,      BTN_MIDDLE, spawn,             {.v = termcmd} },
	{ ClkClient,   MODKEY, BTN_LEFT,   moveresize,        {.ui = CurMove} },
	{ ClkClient,   MODKEY, BTN_RIGHT,  moveresize,        {.ui = CurResize} },
	{ ClkClient,   MODKEY, BTN_SIDE,   togglefloating,    {0} },
	{ ClkClient,   MODKEY, BTN_EXTRA,  togglefloatcenter, {0} },
	{ ClkTagBar,   0,      BTN_LEFT,   view,              {0} },
	{ ClkTagBar,   0,      BTN_RIGHT,  toggleview,        {0} },
	{ ClkTagBar,   MODKEY, BTN_LEFT,   tag,               {0} },
	{ ClkTagBar,   MODKEY, BTN_RIGHT,  toggletag,         {0} },
};

static const Axis axes[] = {
	{ MODKEY, AxisDown, shiftview, {.i = +1} },
	{ MODKEY, AxisUp,   shiftview, {.i = -1} },
};
