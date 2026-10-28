/* See LICENSE file for copyright and license details. */

#include <X11/XF86keysym.h>

/* appearance */
static const unsigned int borderpx  = 1;        /* border pixel of windows */
static const unsigned int snap      = 32;       /* snap pixel */
static const int showbar            = 1;        /* 0 means no bar */
static const int topbar             = 1;        /* 0 means bottom bar */
static const char *fonts[]          = { "DejaVu Sans Mono:size=10" };
static const char dmenufont[]       = "DejaVu Sans Mono:size=10";
static const char col_gray1[]       = "#222222";
static const char col_gray2[]       = "#444444";
static const char col_gray3[]       = "#bbbbbb";
static const char col_gray4[]       = "#eeeeee";
static const char col_gray5[]       = "#777777";
static const char col_gray6[]       = "#999999";
static const char col_cyan[]        = "#005577";
static const char col_blue[]        = "#33a6d9";
static const char *colors[][3]      = {
	/*                   fg         bg         border   */
	[SchemeNorm]     = { col_gray3, col_gray1, col_gray2 },
	[SchemeSel]      = { col_gray4, col_cyan,  col_cyan  },
	[SchemeOcc]      = { col_gray4, col_gray1, col_gray2 }, /* tags with windows */
	[SchemeEmpty]    = { col_gray5, col_gray1, col_gray2 }, /* empty tags */
	/* status text colours, selected by the bytes \x01, \x02, ... in the status */
	[SchemeStatus]   = { col_gray6, col_gray1, col_gray2 }, /* \x01 brackets and labels */
	[SchemeStatus+1] = { col_gray4, col_gray1, col_gray2 }, /* \x02 values */
	[SchemeStatus+2] = { col_blue,  col_gray1, col_gray2 }, /* \x03 now playing */
};

/* tagging */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

static const Rule rules[] = {
	/* xprop(1):
	 *	WM_CLASS(STRING) = instance, class
	 *	WM_NAME(STRING) = title
	 */
	/* class      instance    title       tags mask     isfloating   monitor */
	{ "Gimp",     NULL,       NULL,       0,            1,           -1 },
};

/* layout(s) */
static const float mfact     = 0.55; /* factor of master area size [0.05..0.95] */
static const int nmaster     = 1;    /* number of clients in master area */
static const int resizehints = 1;    /* 1 means respect size hints in tiled resizals */
static const int lockfullscreen = 1; /* 1 will force focus on the fullscreen window */
static const int refreshrate = 240;  /* refresh rate (per second) for client move/resize */

static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "[]=",      tile },    /* first entry is default */
	{ "><>",      NULL },    /* no layout function means floating behavior */
	{ "[M]",      monocle },
};

/* key definitions */
#define MODKEY Mod4Mask
#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

/* helper for spawning shell commands in the pre dwm-5.0 fashion */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* commands */
static char dmenumon[2] = "0"; /* component of dmenucmd, manipulated in spawn() */
static const char *dmenucmd[] = { "dmenu_run", "-m", dmenumon, "-fn", dmenufont, "-nb", col_gray1, "-nf", col_gray3, "-sb", col_cyan, "-sf", col_gray4, NULL };
static const char *termcmd[]  = { "kitty", NULL };
static const char *filecmd[]  = { "thunar", NULL };
static const char *menucmd[]  = { "rofi", "-show", "drun", NULL };

static void
togglefullscreen(const Arg *arg)
{
	if (selmon->sel)
		setfullscreen(selmon->sel, !selmon->sel->isfullscreen);
}

/* view the next/previous tag that has windows on it */
static void
shiftview(const Arg *arg)
{
	Client *c;
	unsigned int occ = 0, cur = selmon->tagset[selmon->seltags];
	int i, n = LENGTH(tags);
	Arg a;

	for (c = selmon->clients; c; c = c->next)
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
	Client *c = selmon->sel;

	if (!c || c->isfullscreen)
		return;
	togglefloating(NULL);
	if (c->isfloating)
		resize(c, selmon->wx + selmon->ww * 20 / 100, selmon->wy + selmon->wh * 35 / 200,
			selmon->ww * 60 / 100 - 2 * c->bw, selmon->wh * 65 / 100 - 2 * c->bw, 0);
}

static const Key keys[] = {
	/* modifier                     key        function        argument */
	{ MODKEY,                       XK_Return, spawn,          {.v = termcmd } },
	{ MODKEY,                       XK_q,      killclient,     {0} },
	{ MODKEY|ShiftMask,             XK_x,      quit,           {0} },
	{ MODKEY,                       XK_e,      spawn,          {.v = filecmd } },
	{ MODKEY,                       XK_u,      togglefloating, {0} },
	{ MODKEY,                       XK_f,      togglefullscreen, {0} },
	{ MODKEY,                       XK_d,      spawn,          {.v = menucmd } },
	{ MODKEY,                       XK_j,      zoom,           {0} },
	{ MODKEY,                       XK_Left,   focusstack,     {.i = -1 } },
	{ MODKEY,                       XK_Up,     focusstack,     {.i = -1 } },
	{ MODKEY,                       XK_Right,  focusstack,     {.i = +1 } },
	{ MODKEY,                       XK_Down,   focusstack,     {.i = +1 } },
	{ MODKEY,                       XK_h,      setmfact,       {.f = -0.05} },
	{ MODKEY,                       XK_l,      setmfact,       {.f = +0.05} },
	{ MODKEY,                       XK_space,  setlayout,      {0} },
	{ MODKEY,                       XK_b,      togglebar,      {0} },
	{ MODKEY,                       XK_Tab,    view,           {0} },
	{ MODKEY,                       XK_0,      view,           {.ui = ~0 } },
	{ MODKEY|ShiftMask,             XK_0,      tag,            {.ui = ~0 } },
	{ MODKEY,                       XK_comma,  focusmon,       {.i = -1 } },
	{ MODKEY,                       XK_period, focusmon,       {.i = +1 } },
	{ MODKEY|ShiftMask,             XK_comma,  tagmon,         {.i = -1 } },
	{ MODKEY|ShiftMask,             XK_period, tagmon,         {.i = +1 } },
	TAGKEYS(                        XK_1,                      0)
	TAGKEYS(                        XK_2,                      1)
	TAGKEYS(                        XK_3,                      2)
	TAGKEYS(                        XK_4,                      3)
	TAGKEYS(                        XK_5,                      4)
	TAGKEYS(                        XK_6,                      5)
	TAGKEYS(                        XK_7,                      6)
	TAGKEYS(                        XK_8,                      7)
	TAGKEYS(                        XK_9,                      8)

	/* multimedia keys */
	{ 0, XF86XK_AudioRaiseVolume,  spawn, SHCMD("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+") },
	{ 0, XF86XK_AudioLowerVolume,  spawn, SHCMD("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") },
	{ 0, XF86XK_AudioMute,         spawn, SHCMD("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") },
	{ 0, XF86XK_AudioMicMute,      spawn, SHCMD("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle") },
	{ 0, XF86XK_MonBrightnessUp,   spawn, SHCMD("brightnessctl -e4 -n2 set 5%+") },
	{ 0, XF86XK_MonBrightnessDown, spawn, SHCMD("brightnessctl -e4 -n2 set 5%-") },
	{ 0, XF86XK_AudioNext,         spawn, SHCMD("playerctl next") },
	{ 0, XF86XK_AudioPause,        spawn, SHCMD("playerctl play-pause") },
	{ 0, XF86XK_AudioPlay,         spawn, SHCMD("playerctl play-pause") },
	{ 0, XF86XK_AudioPrev,         spawn, SHCMD("playerctl previous") },
};

/* button definitions */
/* click can be ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle, ClkClientWin, or ClkRootWin */
static const Button buttons[] = {
	/* click                event mask      button          function        argument */
	{ ClkStatusText,        0,              Button2,        spawn,          {.v = termcmd } },
	{ ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
	{ ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
	{ ClkClientWin,         MODKEY,         8,              togglefloating, {0} },
	{ ClkClientWin,         MODKEY,         9,              togglefloatcenter, {0} },
	{ ClkClientWin,         MODKEY,         Button4,        shiftview,      {.i = -1 } },
	{ ClkClientWin,         MODKEY,         Button5,        shiftview,      {.i = +1 } },
	{ ClkRootWin,           MODKEY,         Button4,        shiftview,      {.i = -1 } },
	{ ClkRootWin,           MODKEY,         Button5,        shiftview,      {.i = +1 } },
	{ ClkTagBar,            0,              Button1,        view,           {0} },
	{ ClkTagBar,            0,              Button3,        toggleview,     {0} },
	{ ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
	{ ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
};
