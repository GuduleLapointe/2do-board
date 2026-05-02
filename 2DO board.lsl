// 2DO board dev
//
string version = "3.0.5";
//
// In-word teleporter board for 2DO events server.
//
// * Get the latest version in-world at Speculoos Lab:
//	hop://speculoos.world:8002/Lab
// * or from git repository
//	https://github.com/GuduleLapointe/2do-board
//
// Licence: GPLv3
// © 2018-2026 Gudule Lapointe <gudule@speculoos.world>
//	Initial script by Tom Frost <tomfrost@linkwater.org>

////////////////////////////
// The following functions must be enabled in the OpenSimulator [OSSL] section.
// (allow_osFunctioName = ...)
//	osDraw (osDrawImage, osDrawLine, osDrawText, osGetDrawStringSize)
//	osGetGridGatekeeperURI,
//	osGetGridLoginURI
//	osGetNotecard
//	osMovePen
//	osSetDynamicTextureDataBlendFace
//	osSetDynamicTextureURLBlendFace
//	osSetFontName
//	osSetFontSize
//	osSetPenColor
//	osSetPenSize
//	osTeleportAgent

////////////////////////////
// DO NOT MOFIFY VALUES HERE
// They would be overridden by updates
// Instead, update the  "Configuration" notecard inside the prim

integer DEBUG = FALSE;

// string theme = "Terminal";
integer showPastEvents = FALSE;

string teleportMethod = "dialog"; // {dialog|map|teleport}

string backgroundColor = "white";
string fontColor = "black";
string colorPast = "lightGray";
string colorStarted = "darkGreen";
string colorSoon = "darkBlue";
string colorToday = "gray";
string colorLater = "lightGray";
string colorHour = "darkMagenta";

string mainFontName = "Junction";
integer mainFontSize=16;

string hourFontName = "";
integer hourFontSize = 12;

float refreshTime = 1800; // In seconds, 1800 = 30 minutes. Lower values for debug only.
float listenTimeout = 300; // Clear llDialog

integer updateWarning = TRUE;
integer sendSimInfo = FALSE;

integer lineHeight = 28;
integer cellPadding = 0;
integer bannerHeight = 90;
integer textureWidth = 512;
integer textureHeight = 512;
list activeSides = [ 1,2,3,4 ];
//list activeSides = [ 0,1,2,3,4,5 ];
//list activeSides = ALL_SIDES; // Unless the object is a perfect cube, use explicit list instead
float ratioCap = 0.25; // Do not update face if side ratio is extreme (e.g. flat panels)
float ratio = 0.0; // Leave 0.0 to calculate ratio from actual side dimensions

// API URL. {v3 API compatible URL|empty}
//Provides events list and/or server-side board image rendering
// Needed for server-side board image rendering
// Leave empty to use legacy v2 API
string apiURL = "https://2do.directory/api/v3";
//string apiURL;

// Events source URL {v2 or v3 compatible events list} (default: 2do API events)
// Leave empty to use default events from API
// Override in Configuration notecard to use a custom source with v2 API.
string eventsURL; // Ignored in API v3, leave apiURL empty to use  custom sourcestring eventsURL = "https://2do.directory/api/v3/events/lsl";   // Official v3 URL
//string eventsURL = "https://2do.directory/api/v3/events/lsl";   // Official v3 URL
//string eventsURL = "https://2do.directory/api/v2/events/lsl";	// Official v2 URL
//string eventsURL = "https://2do.directory/events/events.lsl2"; // Legacy URL

// Set renderer="server" to use v3 server-side PNG board image instead of osDrawText.
// ratio = board face width/height (e.g. 0.75 for a 1.5×2 m board, 1.0 for square).
// Set ratio=0 to auto-detect from prim scale.
string renderer = ""; // {server|osdraw} (default server)

string bannerLink = "https://2do.directory/";
string bannerImageURL = "https://2do.directory/events-dev/2do-logo.png";
string bannerText = "";

// ========================
// internals, do not modify

// Constants
string configFile = "Configuration";
key initImageKey="7fca4681-d388-4d69-971a-d884b4586f22";
vector defaultLandingPoint = <128.0, 128.0, 23.0>;
vector defaultLookAt = <1.0, 1.0, 0.0>;

// Live data, will be overridden
string gatekeeperURI;
list events;
list eventIndices;
integer channel;
integer listenHandle;
integer listening = 0;
key eventsV2RequestID;
string httpSimInfo;
string httpUserAgent;
list avatarDestinations = [];
float touchStarted;

// Event data — parallel lists keyed by ratioStr ("osdraw", "1.0", "0.5", …)
// Each entry is a v3 CSV body with real x0,y0,x1,y1 positions.
// osDraw positions are computed locally after drawing; server positions come from the server.
list eventsDataRatios = [];
list eventsData	   = [];

// Texture UUID cache — parallel lists keyed by ratioStr
list textureRatios = [];
list textureIDs	= [];

// Inflight per-ratio requests — strided list [requestKey, ratioStr, …]
list clickmapRequests = [];

// ==========================
// Automatic updates provider

debug(string message)
{
	if(DEBUG) llOwnerSay(message);
}

string scrupURL = ""; // Leave empty to use API update server
integer scrupAllowUpdates = TRUE; // set to FALSE only for debugging
integer scrupSayVersion = TRUE; // announces version to owner after start or update
integer scrupPin = 56748;
string scrupRequestID; // set dynamically, used in http_response handler

scrup(integer enable) {
	// Uncomment the loginURI for your platform, comment or delete the other
	string loginURI = osGetGridLoginURI();  // If in OpenSimulator
	// string loginURI = "secondlife://";   // If in Second Life

	string scrupVersion = "1.2.0";

	if(scrupURL == "" && apiURL != "") {
		scrupURL = apiURL + "/scrup";
	}
	if (loginURI == "" || scrupURL == "" || !scrupAllowUpdates || !enable) {
		if (loginURI == "") llOwnerSay("loginURI not set, auto-updates disabled");
		else if (scrupURL == "") llOwnerSay("scrupURL not set, auto-updates disabled");
		llSetRemoteScriptAccessPin(0);
		return;
	}

	debug("scrupURL: " + scrupURL);
	debug(llGetScriptName() + " stored version: " + version);

	// Detect API style: legacy (.php URL uses POST body params) vs REST (path-based)
	string clientEndpoint;
	string scriptname;
	string scriptnameVersion = "";

	list extraParams;
	if (llSubStringIndex(scrupURL, ".php") >= 0) {
		clientEndpoint = scrupURL;
		extraParams = ["action=register", "type=client"];
	} else {
		clientEndpoint = scrupURL + "/register/client";
		extraParams = [];
	}

	// Extract version from script name (first token matching x.y.z[-suffix])

	list parts = llParseString2List(llGetScriptName(), [" "], []);
	integer i;
	for (i = 1; i < llGetListLength(parts); i++) {
		string part = llList2String(parts, i);
		string main = llList2String(llParseString2List(part, ["-"], []), 0);
		if (llGetListLength(llParseString2List(main, ["."], [])) > 1
		&& llGetListLength(llParseString2List(main, [".", 0,1,2,3,4,5,6,7,8,9], [])) == 0) {
			scriptnameVersion = part;
			scriptname = llDumpList2String(llList2List(parts, 0, i - 1), " ");
			jump versionFound;
		}
	}
	scrupAllowUpdates = FALSE;
	llSetRemoteScriptAccessPin(0);
	return;

	@versionFound;

	debug(scriptname + " version from name: " + scriptnameVersion);
	if(version != "" && version != scriptnameVersion) {
		llOwnerSay("Inventory name does not match the inside version. To avoid update conflicts,"
			+ "\nyou should rename \"" + llGetScriptName() + "\" as \"" + scriptname + " " + version + "\""
		);
	}

	// After an update, announce version and delete any older copy in inventory
	if (llGetStartParameter() == scrupPin) {
		if (scrupSayVersion || DEBUG) llOwnerSay(scriptname + " found version " + version);
		scrupSayVersion = FALSE;
		i = 0; do {
			string found = llGetInventoryName(INVENTORY_SCRIPT, i);
			if (found != llGetScriptName() && llSubStringIndex(found, scriptname + " ") == 0) {
				llOwnerSay("removing previous version '" + found + "'");
				llRemoveInventory(found);
			}
		} while (i++ < llGetInventoryNumber(INVENTORY_SCRIPT) - 1);
	}

	list params = [
		"loginURI=" + loginURI,
		"linkkey=" + (string)llGetKey(),
		"scriptname=" + scriptname,
		"pin=" + (string)scrupPin,
		"version=" + version,
		"scrupVersion=" + scrupVersion
	] + extraParams;
	scrupRequestID = llHTTPRequest(
		clientEndpoint,
		[HTTP_METHOD, "POST", HTTP_MIMETYPE, "application/x-www-form-urlencoded"],
		llDumpList2String(params, "&")
	);
	llSetRemoteScriptAccessPin(scrupPin);
}

integer boolean(string val)
{
	if(llToUpper(val) == "TRUE" | llToUpper(val) == "YES" | (integer)val == TRUE)
	{
		return TRUE;
	}
	return FALSE;
}

getConfig() {
	if(llGetInventoryType(configFile) == INVENTORY_NOTECARD) {
		string data = osGetNotecard(configFile);
		list lines = llParseString2List (data,["\n"],[]);
		integer i; for (i=0;i<llGetListLength (lines);i++)
		{
			string line = llList2String(lines,i);
			list parse  = llParseStringKeepNulls (line, ["="],[]);
			string configVar = llStringTrim(llList2String(parse, 0), STRING_TRIM);
			// Normalize key: lowercase, strip underscores — accepts old ALL_CAPS_UNDERSCORE and new camelCase
			string var = llToLower(llDumpList2String(llParseString2List(configVar, ["_"], []), ""));

			// Rejoin from index 1 onward so values containing "=" (e.g. query-string URLs) are preserved
		string val = llStringTrim(llDumpList2String(llList2List(parse, 1, -1), "="), STRING_TRIM);

			// Process parameters

			// if (var == "theme") theme = (string)val;
			if (var == "showpastevents") showPastEvents = boolean(val);
			else if (var == "updatewarning") updateWarning = boolean(val);
			else if (var == "sendsiminfo") sendSimInfo = boolean(val);

			else if (var == "texturewidth" && val!="") textureWidth = (integer)val;
			else if (var == "textureheight" && val!="") textureHeight = (integer)val;
			else if (var == "logourl") bannerImageURL = (string)val;
			else if (var == "bannerimageurl") bannerImageURL = (string)val;
			else if (var == "bannerheight") bannerHeight = (integer)val;
			else if (var == "lineheight") lineHeight = (integer)val;
			else if (var == "cellpadding") cellPadding = (integer)val;

			else if (var == "mainfontname" && val!="") mainFontName = (string)val;
			else if (var == "mainfontsize" && val!="") mainFontSize = (integer)val;
			else if (var == "hourfontname") hourFontName = (string)val;
			else if (var == "hourfontsize" && val!="") hourFontSize = (integer)val;

			else if (var == "eventsurl" && val!="") eventsURL = (string)val;
			else if (var == "renderer") renderer = llToLower((string)val);
			else if (var == "ratio" && val!="") ratio = (float)val;
			else if (var == "ratiocap" && val!="") ratioCap = (float)val;

			else if (var == "backgroundcolor") backgroundColor = (string)val;
			else if (var == "fontcolor") fontColor = (string)val;
			else if (var == "colorpast") colorPast = (string)val;
			else if (var == "colorstarted") colorStarted = (string)val;
			else if (var == "colorsoon") colorSoon = (string)val;
			else if (var == "colortoday") colorToday = (string)val;
			else if (var == "colorlater") colorLater = (string)val;
			else if (var == "colorhour") colorHour = (string)val;
			else if (var == "teleportmethod" && val!="") teleportMethod = (string)val;
			else if (var == "activesides" && val!="") {
				list sides = llParseString2List(val, [",","]","["," "], []);
				activeSides = [];
				integer s;
				for (s=0;s<llGetListLength(sides); ++s) {
					activeSides += [llList2Integer(sides, s)];
				}
			//} else {
			//	debug("Unsupported parameter " + configVar + " = " + (string)val);
			}
		}

	}

	// debug("active sides: " + llDumpList2String(activeSides, "; "));

	// Sanitize renderer, apiURL and eventsURL

	// eventsURL	| apiURL	| result
	// empty/v3		| set		| eventsURL = apiURL + "/events/lsl", renderer untouched
	// empty/v3		| empty		| eventsURL = apiURL + "/events/lsl", renderer untouched
	// custom		| set		 | eventsURL untouched, renderer osdraw
	// custom		| empty		| eventsURL untouched, renderer untouched

	// Set eventsURL
	string fallbackEventsURL = "https://2do.directory/api/v3/events/lsl";
	if(eventsURL == "") {
		if( apiURL != "") {
			eventsURL = apiURL + "/events/lsl";
		} else {
			eventsURL = fallbackEventsURL;
		}
	}
	// debug("events URL "  + eventsURL);

	// First set default renderer unless valid option
	if (renderer == "v2" || renderer == "lsl2" || renderer == "osdraw" || apiURL == "") {
		renderer = "osdraw";
	} else {
		renderer = "server";
	}

	// Now make sur renderer is compatible
	string checkEventsURL = eventsURL;
	integer qIdx = llSubStringIndex(eventsURL, "?");
	if (qIdx != -1) checkEventsURL = llGetSubString(eventsURL, 0, qIdx - 1);
	if(renderer == "server" && checkEventsURL != (apiURL + "/events/lsl") && checkEventsURL != fallbackEventsURL) {
		llOwnerSay("renderer: fallback to osdraw, custom source " + eventsURL + " is not compatible with server-side rendering");
		renderer = "osdraw";
	//} else {
	//	debug("renderer " + renderer);
	}

	if (backgroundColor == "transparent") {
		backgroundColor = TEXTURE_TRANSPARENT;
	}

	if(hourFontName=="") hourFontName = mainFontName;
}

//
// manipulate global avatarDestinations list
//
// insert or overwrite destination for agent with dest
//
setAvatarDest(key agent, string dest)
{
	list newList = [];
	integer idx;
	integer len = llGetListLength(avatarDestinations)/2;
	integer set = FALSE;

	for(idx=0;idx<len;idx++) {
		key avatar = llList2Key(avatarDestinations, (idx*2));
		if(avatar==agent) {
		newList += [ agent, dest ];
		set = TRUE;
		} else {
		newList += [ avatar, llList2String(avatarDestinations, (idx*2)+1) ];
		}
	}
	if(!set) {
		newList += [ agent, dest ];
	}

	avatarDestinations = newList;
}

//
// retrieve avatar dest from global avatarDestination list
//
// returns teleportURL if destination set, NULL_KEY otherwise
//
string getAvatarDest(key agent)
{
	integer idx;
	integer len = llGetListLength(avatarDestinations)/2;

	for(idx=0;idx<len;idx++) {
		if(llList2Key(avatarDestinations, (idx*2))==agent) {
		return llList2String(avatarDestinations, (idx*2)+1);
		}
	}
	return NULL_KEY;
}

float getFaceRatio(integer face)
{
	// Bypass calculation to honor custom ratio if configured
	if (ratio > 0) return ratio;

	integer primType = llList2Integer(llGetPrimitiveParams([PRIM_TYPE]), 0);
	if (primType == PRIM_TYPE_BOX) {
		vector scale = llGetScale();
		if (face == 0 || face == 5) return scale.x / scale.y;  // top, bottom
		if (face == 1 || face == 3) return scale.x / scale.z;  // front, back
		if (face == 2 || face == 4) return scale.y / scale.z;  // left, right
	}
	return 1.0;
}

// Returns the face ratio if valid per ratioCap, or -1 to signal the face should be skipped.
float getValidFaceRatio(integer face)
{
	float faceRatio = getFaceRatio(face);
	if (ratioCap > 0 && (faceRatio < ratioCap || faceRatio > 1.0/ratioCap)) {
		return -1;
	}
	return faceRatio;
}

key requestAPI(string endpoint, list args) {
	string endpointURL;

	if(apiURL != "") {
		endpointURL = apiURL + "/" + endpoint;
	} else if(eventsURL != "") {
		endpointURL = eventsURL;
	} else {
		llOwnerSay("Error: one of apiURL or eventsURL must be set, board disabled");
		return NULL_KEY;
	}
	if (sendSimInfo) {
		args += ["ref=" + httpSimInfo];
	}

	if(args != []) {
		endpointURL += "?" + llDumpList2String(args, "&");
	}
	return llHTTPRequest(
		endpointURL + httpUserAgent,
		[ HTTP_BODY_MAXLENGTH, 16384 ],
		""
	);
}

refreshEvents()
{
	eventsDataRatios = [];
	eventsData	   = [];
	if (renderer == "osdraw") {
		eventsV2RequestID = requestAPI("events/lsl", ["renderer=osdraw"]);
		return;
	}
	refreshTexturePNG();
}

string trimText(string in, string fontname, integer fontsize,integer width)
{
	integer i;
	integer trimmed = FALSE;

	for(;llStringLength(in)>0;in=llGetSubString(in,0,-2)) {
		vector extents = osGetDrawStringSize("vector",in,fontname,fontsize);
		if(extents.x<=width) {
			if(trimmed) {
				return in + "…";
			} else {
				return in;
			}
		}
		trimmed = TRUE;
	}

	return "";
}

refreshTexturePNG()
{
	// debug("fetching PNG texture from server " + eventsURL);

	string contentType = "image";
	string extraParams = "width:" + (string)textureWidth + ",height:" + (string)textureHeight;
	string dynamicID = ""; // not implemented yet
	integer timer = 0;	// timer is not implemented yet in OSSL
	integer alpha = 255;  // 0 = 100% Transparent 255 = 100% Solid
	integer blend = TRUE; // TRUE = the newly generated texture is iBlended with the appropriate existing ones on the prim
	integer disp = 2;	// 1 = expire deletes the old texture.  2 = temp means that it is not saved to the Database.


	integer i = 0;
	do
	{
		integer face = llList2Integer(activeSides, i);
		float faceRatio = getValidFaceRatio(face);
		if (faceRatio > 0) {
			float renderRatio = faceRatio * (float)textureHeight / (float)textureWidth;
			string ratioStr = (string)renderRatio;
			//string canvasArgs = "ratio=" + ratioStr
			//	+ "&width=" + (string)textureWidth
			//	+ "&height=" + (string)textureHeight;
			list canvasArgs = [
				"ratio=" + ratioStr,
				"width=" + (string)textureWidth,
				"height=" + (string)textureHeight
			];

			// Clickmap: one request per unique ratio (v3 with canvas layout)
			if (llListFindList(clickmapRequests, [ratioStr]) < 0) {
				clickmapRequests += [
					requestAPI("events/lsl", canvasArgs),
					ratioStr
				];
			}

			// PNG texture
			//string pngURL = eventsURL + querySep(eventsURL) + "format=png&" + canvasArgs;
			string pngURL = apiURL + "/events/board.png?" + canvasArgs;
			// debug("pngURL " + pngURL);
			osSetDynamicTextureURLBlendFace(dynamicID, contentType, pngURL, extraParams, blend, disp, timer, alpha, face);
		}
		i++;
	}
	while (i < llGetListLength(activeSides));
}

refreshTexture()
{
	refreshTextureOsDraw();
}

refreshTextureOsDraw()
{
	// debug("generate texture with OSSL osDraw");
	string commandList = "";

	eventIndices = [];

	commandList = osSetPenColor(commandList, colorStarted);
	commandList = osMovePen(commandList, 0, 0);
	if (bannerHeight > 0 && bannerImageURL != "") {
		commandList = osDrawImage(commandList, 512, bannerHeight, bannerImageURL);
	}

	commandList = osSetPenSize(commandList, 1);
	// commandList = osDrawLine(commandList, 0, 80, 512, 80);

	// stride-10: [x0, y0, x1, y1, destination, start_time, start_stamp, end_time, end_stamp, title]
	integer numEvents = llGetListLength(events) / 10;

	integer i;

	integer y = bannerHeight;

	integer secondMargin = 10 + hourFontSize * 7;

	integer notBefore = llGetUnixTime() - (2*3600);
	integer currentTime = llGetUnixTime();

	integer numEventsShown = 0;

	for(i=0;i<numEvents && numEventsShown<15;i++) {
		integer base = i * 10;

		integer startStamp = (integer)llList2String(events, base + 6);

		if (showPastEvents || startStamp > notBefore) {
			eventIndices += i;
			string currentColor;
			if (colorPast != "" && startStamp < currentTime - 3600) {
				currentColor = colorPast;
			} else if (colorStarted != "" && startStamp < currentTime) {
				currentColor = colorStarted;
			} else if (colorSoon != "" && startStamp < currentTime + 2 * 3600) {
				currentColor = colorSoon;
			} else if (colorToday != "" && startStamp < currentTime + 24 * 3600) {
				currentColor = colorToday;
			} else {
				currentColor = fontColor;
			}

			commandList = osMovePen(commandList, 10, y + 1 + cellPadding);
			if(colorHour != "") {
				commandList = osSetPenColor(commandList, colorHour);
			} else {
				commandList = osSetPenColor(commandList, currentColor);
			}
			commandList = osSetFontName(commandList, hourFontName);
			commandList = osSetFontSize(commandList, hourFontSize);
			commandList = osDrawText(commandList, llList2String(events, base + 5));

			commandList = osSetPenColor(commandList, currentColor);
			string text = llList2String(events, base + 9);
			text = trimText(text, mainFontName, mainFontSize, textureWidth - 30 - secondMargin);
			commandList = osMovePen(commandList, secondMargin, y + cellPadding);
			commandList = osSetFontName(commandList, mainFontName);
			commandList = osSetFontSize(commandList, mainFontSize);
			commandList = osDrawText(commandList, text);

			y += lineHeight;
			numEventsShown++;
		}
	}

	integer alpha = 255;
	if (backgroundColor == TEXTURE_TRANSPARENT) {
		alpha = 0;
	}

	i = 0;
	do
	{
		integer face=llList2Integer(activeSides, i);
		float faceRatio = getValidFaceRatio(face);
		if (faceRatio > 0) {
			osSetDynamicTextureDataBlendFace("", "vector", commandList, "width:"+(string)textureWidth+",height:"+(string)textureHeight
			+ ",bgcolor:" + backgroundColor
			+ ",alpha:" + (string)alpha, FALSE,1, 0,alpha,face);
		}
		i++;
	}
	while (i < llGetListLength(activeSides));

	// Build eventsData for osDraw: v3 CSV with locally-computed UV positions.
	// Same 10-column format as the server response so touch_end is identical.
	float bannerFrac = (float)bannerHeight / (float)textureHeight;
	float lineHeightFrac = (float)lineHeight / (float)textureHeight;
	string body = "0,0,1," + (string)bannerFrac + ",href:" + bannerLink + "\n";
	integer numShown = llGetListLength(eventIndices);
	integer ei;
	for (ei = 0; ei < numShown; ei++) {
		float rowY0 = bannerFrac + (float)ei * lineHeightFrac;
		float rowY1 = rowY0 + lineHeightFrac;
		integer evIdx = llList2Integer(eventIndices, ei);
		integer base = evIdx * 10;
		string title = llList2String(events, base + 9);
		// CSV-quote the title if it contains commas or double-quotes
		if (llSubStringIndex(title, ",") != -1 || llSubStringIndex(title, "\"") != -1) {
			title = "\"" + llDumpList2String(llParseStringKeepNulls(title, ["\""], []), "\"\"") + "\"";
		}
		body += "0," + (string)rowY0 + ",1," + (string)rowY1 + ","
			+ llList2String(events, base + 4) + ","   // destination
			+ llList2String(events, base + 5) + ","   // start_time
			+ llList2String(events, base + 6) + ","   // start_stamp
			+ llList2String(events, base + 7) + ","   // end_time
			+ llList2String(events, base + 8) + ","   // end_stamp
			+ title + "\n";
	}
	integer existing = llListFindList(eventsDataRatios, ["osdraw"]);
	if (existing != -1) {
		eventsData = llListReplaceList(eventsData, [body], existing, existing);
	} else {
		eventsDataRatios += ["osdraw"];
		eventsData	   += [body];
	}
 }

openWebPage(key avatar, string url)
{
	// debug("openWebPage → " + url);
	llLoadURL(avatar, "Visit 2DO.pm/events for a detailed full list of upcoming events.", url);
}

teleportRoute(key avatar, string teleportURL, string title)
{
	//debug("teleportRoute → " + teleportURL);
	if(teleportMethod == "map") {
		teleportMap(teleportURL);
		return;
	} else if(teleportMethod == "teleport") {
		teleportAvatar(avatar, teleportURL);
		return;
	}

	// Dialog confirmation — show title (full, possibly un-truncated) above the URL
	setAvatarDest(avatar, teleportURL);
	string msg = "\n";
	if (title != "") msg += title + "\n";
	msg += teleportURL + "\n\n";
	llDialog(avatar, msg, ["Teleport", "Cancel"], channel);
	if(listening==0) {
		listenHandle = llListen(channel, "", NULL_KEY, "");
		listening = (integer)llGetTime();
	}
}

teleportAvatar(key avatar, string teleportURL) {
	// TODO: extract landingPoint from url if provided
	vector landingPoint = defaultLandingPoint;
	vector lookAt = defaultLookAt;
	if (teleportURL != NULL_KEY) {
		//debug( "disabled for debug: osTeleportAgent(" + avatar + ", " + teleportURL);
		//if(DEBUG) return;
		osTeleportAgent(avatar, teleportURL, landingPoint, lookAt);
		return;
	}
	// debug("teleportAvatar called with null key");
}

teleportMap(string teleportURL) {
	//debug("teleportMap → " + teleportURL);
	// TODO: extract landingPoint from url if provided
	vector landingPoint = defaultLandingPoint;
	vector lookAt = defaultLookAt;
	llMapDestination(teleportURL, landingPoint, ZERO_VECTOR);
}

string strReplace(string str, string search, string replace) {
	return llDumpList2String(llParseStringKeepNulls((str),[search],[]),replace);
}

// Return "?" or "&" depending on whether url already has a query string.
string querySep(string url) {
	if (llSubStringIndex(url, "?") != -1) return "&";
	return "?";
}

// Parse v3 CSV body into stride-10 events list.
// Skips banner rows (destination starts with "href:").
// Stride: [x0, y0, x1, y1, destination, start_time, start_stamp, end_time, end_stamp, title]
list parseV3(string body)
{
	list result = [];
	list lines = llParseString2List(body, ["\n"], []);
	// debug("parseV3 received " + llGetListLength(lines) + " lines" + " from " + eventsURL);
	integer numLines = llGetListLength(lines);
	integer li;
	for (li = 0; li < numLines; li++) {
		string line = llList2String(lines, li);
		if (line == "") jump nextLineV3;
		list parts = llCSV2List(line);
		if (llGetListLength(parts) < 10) jump nextLineV3;
		string dest = llList2String(parts, 4);
		if (llGetSubString(dest, 0, 4) == "href:") jump nextLineV3;
		result += [
			llList2String(parts, 0),  // x0
			llList2String(parts, 1),  // y0
			llList2String(parts, 2),  // x1
			llList2String(parts, 3),  // y1
			dest,					 // destination
			llList2String(parts, 5),  // start_time
			llList2String(parts, 6),  // start_stamp
			llList2String(parts, 7),  // end_time
			llList2String(parts, 8),  // end_stamp
			llList2String(parts, 9)   // title
		];
		@nextLineV3;
	}
	// debug("parseV3 parsed " + (string)(llGetListLength(result)/10) + " events");
	list firstEvent = llList2List(result, 4, 9);
	// debug("First event: " + llDumpList2String(firstEvent, " -- "));
	return result;
}

// Parse lsl2 body (version + groups of 3 lines: title/timespec/dest) into stride-10 events list.
// Positions are set to 0 since lsl2 has no layout information.
// Stride: [x0, y0, x1, y1, destination, start_time, start_stamp, end_time, end_stamp, title]
list parseLsl2(string body)
{
	list result = [];
	list lines = llParseString2List(body, ["\n"], []);
	// debug("parseLsl2 received " + llGetListLength(lines) + " lines" + " from " + eventsURL);
	integer numLines = llGetListLength(lines);
	integer li = 1; // skip version line
	while (li + 2 < numLines) {
		string title	= llList2String(lines, li);
		string timespec = llList2String(lines, li + 1);
		string dest	 = llList2String(lines, li + 2);
		if (title != "" && timespec != "" && dest != "") {
			// timespec: start_time~start_date~start_stamp~end_time~end_date~end_stamp
			list ts = llParseString2List(timespec, ["~"], []);
			result += [
				0,  // x0, not implemented in v2
				0,  // y0, not implemented in v2
				0,  // x1, not implemented in v2
				0,  // y1, not implemented in v2
				dest,  // destination, not implemented in v2
				llList2String(ts, 0),  // start_time
				llList2String(ts, 2),  // start_stamp
				llList2String(ts, 3),  // end_time
				llList2String(ts, 5),  // end_stamp
				title
			];
		}
		li += 3;
	}
	// debug("parseLsl2 parsed " + (string)(llGetListLength(result)/10) + " events");
	list firstEvent = llList2List(result, 4, 9);
	// debug("First event: " + llDumpList2String(firstEvent, " -- "));
	return result;
}

initTextures()
{
	integer i = 0;
	do
	{
		integer face = llList2Integer(activeSides, i);
		if (getValidFaceRatio(face) > 0) {
			llSetTexture(initImageKey, face);
		}
		i++;
	}
	while (i < llGetListLength(activeSides));
}

default
{
	state_entry()
	{
		scrup(ACTIVE);
		channel = -25673 - (integer)llFrand(1000000);
		gatekeeperURI = strReplace(osGetGridGatekeeperURI(), "http://", "");
		//debug("gatekeeperURI " + gatekeeperURI);
		getConfig();
		initTextures();

		listening = 0;
		avatarDestinations = [];
		llSetTimerEvent(refreshTime);
		httpUserAgent=" HTTP/1.0\nUser-Agent: LSL Script (Mozilla Compatible)" + "\n\n";
		if(sendSimInfo) {
			httpSimInfo = llGetScriptName()
			+ "/" + version
			+ " " + osGetGridGatekeeperURI() + ":" + llGetRegionName();
		}
		refreshEvents();
	}

	http_response(key requestID, integer status, list metadata, string body)
	{
		//if(requestID == scrupRequestID) {
		//	debug("client register response " + (string)status + "\n" + body);
		//}

		integer cmReqIdx = llListFindList(clickmapRequests, [requestID]);
		if (cmReqIdx != -1) {
			// debug("received eventsData for ratio " + llList2String(clickmapRequests, cmReqIdx + 1));
			string ratioStr = llList2String(clickmapRequests, cmReqIdx + 1);
			clickmapRequests = llDeleteSubList(clickmapRequests, cmReqIdx, cmReqIdx + 1);
			if (status == 200) {
				integer existing = llListFindList(eventsDataRatios, [ratioStr]);
				if (existing != -1) {
					eventsData = llListReplaceList(eventsData, [body], existing, existing);
				} else {
					eventsDataRatios += [ratioStr];
					eventsData	   += [body];
				}
			} else {
				// debug("eventsData error " + (string)status + " for ratio " + ratioStr);
			}
			return;
		}

		if(requestID == eventsV2RequestID) {
			// debug("received data for raw events list");
			string firstLine = llList2String(llParseString2List(body, ["\n"], [""]), 0);
			if(status==200) {
				// Auto-detect format: first non-empty line with a comma → v3 CSV; otherwise → lsl2
				if (llSubStringIndex(firstLine, ",") != -1) {
					events = parseV3(body);
				} else {
					events = parseLsl2(body);
				}
				// stride-10: [x0, y0, x1, y1, destination, start_time, start_stamp, end_time, end_stamp, title]
				refreshTexture();
			} else {
				// TODO: proper error parser to optimize error display on board
				// for both osdraw and server-side renderers
				llOwnerSay("Unable to fetch  events from " + eventsURL
				+ "\nstatus: " + (string)status
				+ "\nmessage: " + (string)body);
				// TODO: handle error messages in parseV3 and parseLsl2
				integer currentTime = llGetUnixTime();
				string message;
				string statusStr = (string)status;
				if(llSubStringIndex(body, "{") == 0) {
					if(llSubStringIndex(body, "\"message\"") >= 0) {
						message = llJsonGetValue(body, ["message"]);
					}
					if(llSubStringIndex(body, "\"error\"") >= 0) {
						statusStr += " " + llJsonGetValue(body, ["error"]);
					}
				}
				if(message == "") {
					message = firstLine;
				}
				events = [
					0, 0, 0, 0,
					"",  // destination, not implemented in v2
					"",  // start_time
					currentTime + 24 * 3600,  // start_stamp
					"",  // end_time
					currentTime + 24 * 3600 * 2,  // end_stamp
					"Error " + statusStr,
					0, 0, 0, 0,
					"",
					"",  // start_time
					currentTime + 24 * 3600,  // start_stamp
					"00:00PM",  // end_time
					currentTime + 24 * 3600 * 2,  // end_stamp
					message,
					0, 0, 0, 0,
					"",
					"",  // start_time
					currentTime + 24 * 3600,  // start_stamp
					"00:00PM",  // end_time
					currentTime + 24 * 3600 * 2,  // end_stamp
					"",
					0, 0, 0, 0,
					"speculoos.world:8002:Lab",
					"",  // start_time
					currentTime + 24 * 3600,  // start_stamp
					"00:00PM",  // end_time
					currentTime + 24 * 3600 * 2,  // end_stamp
					"Latest 2do board at Speculoos lab",
					0, 0, 0, 0,
					"https://2do.directory",
					"",  // start_time
					currentTime + 24 * 3600,  // start_stamp
					"00:00PM",  // end_time
					currentTime + 24 * 3600 * 2,  // end_stamp
					"https://2do.directory"
				];
				refreshTexture();
			}
		}
	}

	listen(integer chan, string name, key agent, string msg)
	{
		if (chan == channel) {
			string teleportURL = getAvatarDest(agent);
			if (msg == "Teleport") {
				teleportAvatar(agent, teleportURL);
			} else if (msg == "Map") {
				teleportMap(teleportURL);
			} else if (msg != "Cancel") {
				llInstantMessage(agent, msg + " is not a valid choice");
			}
		}
	}
	touch_start(integer index)
	{
		touchStarted=llGetTime();
	}
	touch_end(integer num)
	{
		if(llDetectedKey(0)==llGetOwner() && llGetTime() - touchStarted > 2) {
			llResetScript();
		}

		integer i; // Loop is probably overengineering, 0 should be be enough
		for(i=0;i<num;i++) {
			integer link = llDetectedLinkNumber(i);
			vector point = llDetectedTouchST(i);
			integer face = llDetectedTouchFace(i);
			key avatar = llDetectedKey(i);

			if (link != llGetLinkNumber()) {
				//debug("ignore other prim link " + (string)link);
				return;
			}
			if (point == TOUCH_INVALID_TEXCOORD) {
				// debug("TOUCH_INVALID_TEXCOORD " + (string)point);
				return;
			}
			if (activeSides != [ALL_SIDES] && llListFindList(activeSides, face) == -1) {
				// debug("ignore inactive face " + (string)face);
				return;
			}

			// UV fractions from top-left; llDetectedTouchST returns <s,t,0> (s=U, t=V from bottom)
			float touchU = llDetectedTouchST(i).x;
			float touchV = 1.0 - llDetectedTouchST(i).y;
			string ratioKey;

			if (renderer == "osdraw") {
				ratioKey = "osdraw";
			} else {
				float faceRatio = getValidFaceRatio(face);
				if (faceRatio <= 0) {
					// debug("invalid face ratio " + (string)faceRatio);
					return;
				}
				ratioKey = (string)(faceRatio * (float)textureHeight / (float)textureWidth);
			}

			integer evDataIdx = llListFindList(eventsDataRatios, [ratioKey]);
			if (evDataIdx == -1) {
				// debug("no eventsData for ratio " + ratioKey);
				return;
			}

			string debugDetails = " face=" + (string)face + " U=" + (string)touchU + " V=" + (string)touchV + " ratio=" + ratioKey;
			list lines = llParseString2List(llList2String(eventsData, evDataIdx), ["\n"], []);
			integer li;
			for (li = 0; li < llGetListLength(lines); li++) {
				string line = llList2String(lines, li);
				if (line == "") jump nextTouchLine;
				// v3 CSV: x0,y0,x1,y1,destination[,start_time,start_stamp,end_time,end_stamp,title]
				list parts = llCSV2List(line);
				if (llGetListLength(parts) >= 5) {
					float rowX0 = (float)llList2String(parts, 0);
					float rowY0 = (float)llList2String(parts, 1);
					float rowX1 = (float)llList2String(parts, 2);
					float rowY1 = (float)llList2String(parts, 3);
					string destination = llList2String(parts, 4);
					if (touchU >= rowX0 && touchU <= rowX1 && touchV >= rowY0 && touchV <= rowY1) {
						if (llGetSubString(destination, 0, 4) == "href:") {
							openWebPage(avatar, llGetSubString(destination, 5, -1));
						} else {
							teleportRoute(avatar, destination, llList2String(parts, 9));
						}
						return;
					}
				} else {
					// debug("invalid eventsData line: [" + line + "]" + debugDetails);
				}
				@nextTouchLine;
			}
			//debug("not a clickable region" + debugDetails);
		}
	}

	timer()
	{
		// timeout listener
		if(listening!=0) {
			if( (listening + listenTimeout) < (integer)llGetTime() ) {
				debug("Timeout " + listening);
				llListenRemove(listenHandle);
				avatarDestinations=[];
				listening = 0;
			}
		}

		debug("Refresh time " + listening);
		// refresh texture
		refreshEvents();
	}

	on_rez(integer start_param)
	{
		llResetScript();
	}

	changed(integer change)
	{
		if(change & CHANGED_SHAPE ||
		change & CHANGED_SCALE ||
		change & CHANGED_OWNER ||
		change & CHANGED_REGION ||
		(change & CHANGED_INVENTORY && llGetStartParameter() != scrupPin)
		) {
			llResetScript();
		}
	}
}
