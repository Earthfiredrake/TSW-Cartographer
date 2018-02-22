﻿// Copyright 2017-2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-Cartographer

import gfx.utils.Delegate;

import com.GameInterface.Chat; // FIFO messages
import com.GameInterface.DistributedValue;
import com.GameInterface.Log;
import com.GameInterface.Utils; // Chat messages *shrug*
import com.Utils.Archive;
import com.Utils.Signal;

// TODO: Component based behaviour system for lighter weight mods
//       Objective is to remove at least some of these imports
//       Possibly split out some other subsystems and mod behaviours
import efd.Cartographer.lib.LocaleManager;

// Mod Framework v1.1.0
// See ModInfo.LibUpgrades for upgrade requirements

//   As part of ongoing attempts at consistent naming, the following DistributedValue names are reserved for use by the framework or Modules.xml:
//   [pfx] is a developer unique prefix (I use 'efd'), [Name] is the name of the mod
//   Unique per mod name:
//     "[pfx]GameEnables[Name]: The variable defined in Modules.xml as a hard disable for the mod; will disable all features (including icon) and prevent loading in future
//     "[pfx][Name]Enabled": Exists for e_ModType_Reactive mods; "Soft" disable that retains icon and doesn't prevent loading in future; Corresponds to "Enabled" config setting
//     "[pfx][Name]Loaded": Set to true when the mod is fully loaded and initialized
//     "[pfx][Name]Config: Name of archive in which main settings are saved (Mods may use secondary archives for some settings), defined in xml configuration, usually used with the Config system
//     "[pfx][Name]DebugMode: Toggles debug trace messages and other debug/dev tools in an individual mod (persists through /reloadui)
//     "[pfx][Name]ResetConfig": Trigger to reset settings to defaults from chat, created by the Config subsystem
//     "[pfx]Show[Name]ConfigWindow": Toggles the settings window, created by the Config subsystem
//     "[pfx]Show[Name]InterfaceWindow": Toggles an interface window, if one was included in ModData
//   Framework shared; use "emf" prefix and affect all mods built with default versions of this framework:
//     "emfListMods": Mods report their current version and author to system chat
//     "emfNextIconID": Used to create unique offsets on default icon placements, reducing icon pileups when installing multiple mods
//     "emfDebugMode": Toggles debug trace messages globally, may also enable other debug/dev tools (persists through /reloadui)
//   From other mods:
//     "VTIO_IsLoaded", "VTIO_RegisterAddon": VTIO hooks, use of these for other reasons may cause problems with many mods

// Base for mod classes
//   Handles initialization and general mod behaviours:
//     Xml datafile loader
//     Standardized chat output
//     Text localization and string file (via LocaleManager)
//   Additional subsystems that may be applied:
//     Config (ConfigManager.as):
//       Setting serialization and change notification
//       Versioning and upgrade detection
//       Configuration window
//     Icon (ModIcon.as): Icon display with topbar integration and GEM layout options
//     VTIOHelper: Integration with VTIO compatible mod containers and topbars
//     Window: Interface window management
//     AutoReport: Mail based reporting system for errors or other information
//   Subclass is responsible for:
//     Initialization data, including subsystems and their dependencies
//     Additional setting definitions
//     Processing version upgrades
//     Icon and window content (usually in .fla library under default names)
//     Processing datafile content
//     Doing something useful (or at least interesting)

// When adapting any code for another mod:
//   Always use a unique namespace for the mod on all class, import and __className definitions
//     The flash environment caches classes by fully namespace qualified identifier when first encountered
//     Whichever mod loads first gets to be the authoritive definition for all classes it defines
//     This can be helpful if loading order is known (Game API loads before mods), but mods can't otherwise depend on being loaded in any particular order
//   Use similarly unique names, or dynamic linking, for clip library assets
//     Due to similar caching behaviour, where anybody's library asset by that name will use whatever class was linked
//     See etu.MovieClipHelper for functions to do dynamic linking

class efd.Cartographer.lib.Mod {
/// Initialization and Cleanup
	// ModData enum describing basic mod behaviour (ModInfo.Type, being phased out)
	//   Mod hooks to game notifications and responds when triggered (ex: LoreHound, NBG)
	//   Provides option to be toggled between enabled/disbled states
	//   Standard icon behaviours are options window on left and toggle mod on right
	//   Topbar settings icon will open config window, or toggle state if no window is specified
	public static var e_ModType_Reactive:Number = 1;

	// The ModInfo object has the following fields:
	//   Trace (optional, default false)
	//     Enables debug trace messages, usually defined first for easy commenting out
	//   Name:String (required, placeholder default "Unnamed")
	//     The name of the mod, for display and used to generate a variety of default identifiers
	//   Version:String (required, placeholder default "0.0.0")
	//     Current build version
	//     Expects "#.#.#[.alpha|.beta]" format (does not enforce, but may cause issues with upgrade system)
	//   Type:e_ModType (optional, being phased out)
	//     Values described above
	//   Subsystems:Object (optional, default undefined)
	//     A set of keyed pairs Subsystems["Key"] = {Init:Function(Mod, InitObj), InitObj:Object}
	//     Init is a factory method to initialize the required subsystem
	//     InitObj may be adjusted internally prior to the call
	//     Some subsystems have dependencies, Mod ensures correct initialization order but the mod author is responsible for including all dependencies
	//     For full details on dependencies, and param contents, consult the subsystem .as files

	public function Mod(modInfo:Object, hostMovie:MovieClip) {
		FifoMsg = Delegate.create(this, _FifoMsg);
		ChatMsg = Delegate.create(this, _ChatMsg);
		ErrorMsg = Delegate.create(this, _ErrorMsg);
		TraceMsg = Delegate.create(this, _TraceMsg);
		LogMsg = Delegate.create(this, _LogMsg);
		LoadXmlAsynch = Delegate.create(this, _LoadXmlAsynch);

		if (!modInfo.Name) {
			ModName = "Unnamed";
			// Dev message, not localized
			ErrorMsg("Mod requires a name");
		} else { ModName = modInfo.Name; }
		if (!modInfo.Version) {
			modInfo.Version = "0.0.0";
			// Dev message, not localized
			ErrorMsg("Mod expects a version number");
		}
		Version = modInfo.Version;

		GlobalDebugDV = DistributedValue.Create("emfDebugMode");
		GlobalDebugDV.SignalChanged.Connect(SetDebugMode, this);
		LocalDebugDV = DistributedValue.Create(DVPrefix + ModName +  "DebugMode");
		LocalDebugDV.SignalChanged.Connect(SetDebugMode, this);
		DebugTrace = GlobalDebugDV.GetValue() || LocalDebugDV.GetValue() || modInfo.Trace;

 		SignalLoadCompleted = new Signal();
		SystemsLoaded = { LocalizedText: false };
		if (modInfo.Subsystems.Config != undefined) { SystemsLoaded.Config = false; }
		ModLoadedDV = DistributedValue.Create(ModLoadedVarName);
		ModLoadedDV.SetValue(false);
		if (modInfo.Type == e_ModType_Reactive) {
			ModEnabledDV = DistributedValue.Create(ModEnabledVarName);
			ModEnabledDV.SetValue(true);
			ModEnabledDV.SignalChanged.Connect(ToggleUserEnabled, this);
		}

		ModListDV = DistributedValue.Create("emfListMods");
		ModListDV.SignalChanged.Connect(ReportVersion, this);

		LocaleManager.Initialize();
		LocaleManager.SignalStringsLoaded.Connect(StringsLoaded, this);
		LocaleManager.LoadStringFile("Strings");

		HostMovie = hostMovie; // Not needed for console style mods

		ConfigHost = modInfo.Subsystems.Config.Init(this, modInfo.Subsystems.Config.InitObj);
		if (ModEnabledDV != undefined) { Config.NewSetting("Enabled", true); } // Whether mod is enabled by the player
		Config.SignalConfigLoaded.Connect(ConfigLoaded, this);
		Config.SignalValueChanged.Connect(ConfigChanged, this);

		InterfaceWindow = modInfo.Subsystems.Interface.Init(this, modInfo.Subsystems.Interface.InitObj);
		LinkVTIO = modInfo.Subsystems.LinkVTIO.Init(this, modInfo.Subsystems.LinkVTIO.InitObj);
		Icon = modInfo.Subsystems.Icon.Init(this, modInfo.Subsystems.Icon.InitObj);
	}

	private function StringsLoaded(success:Boolean):Void {
		if (success) { UpdateLoadProgress("LocalizedText"); }
		else { ErrorMsg("Unable to load string table", { fatal : true }); } // Localization support unavailable, not localized
	}

	// Notify when a core subsystem has finished loading to ensure that LoadComplete properly triggers
	// Also a convenient place to override and trigger events that require multiple subsystems to be loaded
	private function UpdateLoadProgress(loadedSystem:String):Boolean {
		TraceMsg(loadedSystem + " Loaded");
		SystemsLoaded[loadedSystem] = true;
		for (var system:String in SystemsLoaded) {
			if (!SystemsLoaded[system]) { return false; }
		}
		TraceMsg("Is fully loaded");
		LoadComplete();
	}

	// TODO: Failure to clear the SystemsLoaded object seems to crash reliably when the interface window opens
	//       Investigate and fix. Low priority, currently SystemsLoaded is being cleared/largely unused
	private function LoadComplete():Void {
		delete SystemsLoaded; // No longer required
		ConfigHost.UpdateManager.UpdateInstall();
		// TODO: Load icon invisibly, and only make it visible when loading is successfully complete?
		SignalLoadCompleted.Emit();
		ModLoadedDV.SetValue(true);
	}

	// The game itself toggles the mod's activation state (based on modules.xml criteria)
	public function GameToggleModEnabled(state:Boolean, archive:Archive) {
		if (!state) {
			// DEPRECATED(v1.0.0): Temporary upgrade support
			if (Config.GetValue("TopbarIntegration") == undefined) { Config.SetValue("TopbarIntegration", false); }
			ConfigHost.ConfigWindow.CloseWindow();
			return Config.SaveConfig();
		} else {
			if (!Config.IsLoaded) {	Config.LoadConfig(archive);	}
		}
		EnabledByGame = state;
		Enabled = state;
	}

	// TODO: Completing icon extraction
	public function OnUnload():Void { Icon.FreeID(); }

	private function SetDebugMode(dv:DistributedValue):Void { DebugTrace = dv.GetValue(); }

	// Each mod ends up getting two notifications, whichever mod is "first" gets a true+false, other mods get false+false
	private function ReportVersion(dv:DistributedValue):Void {
		if (dv.GetValue()) { dv.SetValue(false); }
		if (!VersionReported) { ChatMsg(Version + " : " + DevName); }
		VersionReported = !VersionReported;
	}

/// Configuration Settings
	private function ConfigLoaded():Void { UpdateLoadProgress("Config"); }

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		if (setting == "Enabled") {
			if (newValue && SystemsLoaded != undefined) {
				// May not have loaded localization system
				ErrorMsg("Failed to load required information, and cannot be enabled");
				for (var key:String in SystemsLoaded) {
					if (!SystemsLoaded[key]) { ErrorMsg("Missing: " + key, { noPrefix : true }); }
				}
				Config.SetValue("Enabled", false);
			} else {
				Enabled = newValue;
				ModEnabledDV.SetValue(newValue);
				if (Icon == undefined) {
					// No Icon, probably means it's a console style mod
					// Provide alternate notification
					ChatMsg(LocaleManager.GetString("General", newValue ? "Enabled" : "Disabled"));
				}
			}
		}
	}

/// Standard Icon Mouse Behaviour Packages
	public var IconMouse_ToggleUserEnabled:Object = { Action : ToggleUserEnabled, Tooltip : ToggleUserEnabledTooltip };
	public var IconMouse_ToggleInterfaceWindow:Object = { Action : ToggleInterfaceWindow, Tooltip : ToggleInterfaceWindowTooltip };
	public var IconMouse_ToggleConfigWindow:Object = { Action : ToggleConfigWindow, Tooltip : ToggleConfigWindowTooltip };

	// Implementations
	private function ToggleUserEnabled(dv:DistributedValue):Void {
		// This one also used by EnabledDV
		var value:Boolean = dv != undefined ? dv.GetValue() : !Config.GetValue("Enabled");
		Config.SetValue("Enabled", value);
	}
	private function ToggleUserEnabledTooltip():String {
		return LocaleManager.GetString("GUI", Config.GetValue("Enabled") ? "TooltipModOff" : "TooltipModOn");
	}

	private function ToggleInterfaceWindow():Void { InterfaceWindow.ToggleWindow(); }
	private function ToggleInterfaceWindowTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowInterface"); }

	private function ToggleConfigWindow():Void { ConfigHost.ConfigWindow.ToggleWindow(); }
	private function ToggleConfigWindowTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowSettings"); }

/// Data File Loader
	// Loads an XML file from a path local to the mod's directory
	// The '.xml' suffix is added if not present
	public function _LoadXmlAsynch(fileName:String, callback:Function):XML {
		if (fileName.substr(-4) != ".xml") {
			fileName += ".xml";
		}
		var loader:XML = new XML();
		loader.ignoreWhite = true;
		loader.onLoad = callback;
		loader.load(ModName + "\\" + fileName);
		return loader;
	}
	public static var LoadXmlAsynch:Function; // Static delegate

/// Text Output
	// Options object supports the following properties:
	//   system:String - Name of subsystem to include in the prefix
	//   noPrefix:Boolean - Will not display mod or subsystem name if true
	//     Initial messages should probably display this, but it is optional for immediate followup messages
	// Additional properties may be defined for use by the mod itself
	// It is discarded before passing the remaining parameters to the LocaleManager formatting system
	// Parameters passed to the format string are:
	//   %1% : The message text
	//   %2% : The mod prefix text if not disabled
	//   %3% : The subsystem prefix text if it exists and is not disabled
	//   %4%+ : Arbitrary additional parameters passed in by the mod
	// If a format string expects a certain number of parameters, but does not recieve that many it will:
	//   Ignore any extra or unused parameters
	//   Display 'undefined' if an expected parameter is missing
	//     It is therefore important that any additional parameters passed in be defaulted to ""
	private function _FifoMsg(message:String, options:Object):Void {
		var prefixes:Array = GetPrefixes(options);
		arguments.splice(1, 1, prefixes[0], prefixes[1]);
		var args:Array = new Array("General", "FifoMessage").concat(arguments);
		Chat.SignalShowFIFOMessage.Emit(LocaleManager.FormatString.apply(undefined, args), 0);
	}

	private function _ChatMsg(message:String, options:Object):Void {
		var prefixes:Array = GetPrefixes(options);
		arguments.splice(1, 1, prefixes[0], prefixes[1]);
		var args:Array = new Array("General", "ChatMessage").concat(arguments);
		Utils.PrintChatText(LocaleManager.FormatString.apply(undefined, args));
	}

	// Bypasses localization, for errors that can't count on localization support
	// Additional option "fatal": Force disables the mod
	private function _ErrorMsg(message:String, options:Object):Void {
		if (!options.noPrefix) {
			var sysPrefix:String = options.system ? (options.system + " - ") : "";
			message = "<font color='#EE0000'>" + ModName +"</font>:"  + (options.fatal ? " FATAL " : " ") + "ERROR - " + sysPrefix + message + "!";
		}
		Utils.PrintChatText(message);
		if (options.fatal) {
			_ErrorMsg("  Mod disabled", { noPrefix : true });
			// TODO: This setting of Enabled should ensure that Enabled is actually a thing
			//       Should it also ensure that the "Loaded" DV is cleared to lock down interface?
			Config.SetValue("Enabled", false);
		}
	}

	private function _TraceMsg(message:String, options:Object):Void {
		// Debug messages, should be independent of localization system to allow traces before it loads
		if (DebugTrace) {
			if (!options.noPrefix) {
				var sysPrefix:String = options.system ? (options.system + " - ") : "";
				message = "<font color='#FFB555'>" + ModName +"</font>: Trace - " + sysPrefix + message;
			}
		 	Utils.PrintChatText(message);
		}
	}

	// Debug logging, not localized
	public function _LogMsg(message:String):Void { Log.Error(ModName, message); }

	private function GetPrefixes(options:Object):Array {
		var prefixes:Array = new Array("", "");
		if (!options.noPrefix) {
			prefixes[0] = LocaleManager.FormatString("General", "ModMessagePrefix", ModName);
			if (options.system != undefined) {
				prefixes[1] = LocaleManager.FormatString("General", "SubsystemMessagePrefix", options.system);
			}
		}
		return prefixes;
	}

	// Static delegates to the ones above
	// So other components can access them without needing a reference
	// Recommend wrapping the call in a local version, that inserts an identifer for the subcomponent involved
	public static var FifoMsg:Function;
	public static var ChatMsg:Function;
	public static var ErrorMsg:Function;
	public static var TraceMsg:Function;
	public static var LogMsg:Function;

/// Subclass Extension Stubs
	public function InstallMod():Void { }
	public function UpdateMod(newVersion:String, oldVersion:String):Void { }
	private function Activate():Void { }
	private function Deactivate():Void { }
	private function TopbarRegistered(firstTime:Boolean):Void { }

/// Properties and Variables
	public var Version:String;

	public function get Enabled():Boolean { return _Enabled; }
	public function set Enabled(value:Boolean):Void {
		// TODO: This check for Config("Enabled") should be cleaned up for cases where it doesn't exist
		//       Should game trigger Activate/Deactivate pairs for those mods? (affects fallback value choice)
		value = EnabledByGame && Config.GetValue("Enabled");
		if (value != _Enabled) { // State changed
			_Enabled = value;
			if (value) { Activate(); }
			else { Deactivate(); }
		}
	}

	public function get ModLoadedVarName():String { return DVPrefix + ModName + "Loaded"; }
	public function get ModEnabledVarName():String { return DVPrefix + ModName + "Enabled"; }

	// Customize based on mod authorship
	public static var DevName:String = "Peloprata";
	public static var DVPrefix:String = "efd"; // Retain this if making a compatible fork of an existing mod

	public var ModName:String;
	public var SystemsLoaded:Object; // Tracks asynchronous data loads so that functions aren't called without proper data, removed once loading complete
	public var ModLoadedDV:DistributedValue; // Locks-out interface when mod fails to load, may also be used for cross-mod integration
	private var ModListDV:DistributedValue;
	private var VersionReported:Boolean = false;

	private var _Enabled:Boolean = false;
	private var EnabledByGame:Boolean = false;
	// Player enable/disable only applies to reactive mods at this point
	// DV and related config setting will be undefined for interface mods
	private var ModEnabledDV:DistributedValue; // Only reflects the player's setting, doesn't toggle everytime the game triggers it
	// Enabled by player is a persistant config setting

	public var ConfigHost:Object; // Ducktyped ConfigManager
	public var Config:Object; // Ducktyped ConfigWrapper

	private var InterfaceWindow:Object; // Ducktyped Window

	public var HostMovie:MovieClip;
	public var Icon:MovieClip; // Ducktyped ModIcon
	private var LinkVTIO:Object; // Ducktyped VTIOHelper

	public var SignalLoadCompleted:Signal;

	private var DebugTrace:Boolean;
	private var GlobalDebugDV:DistributedValue; // Used to quickly toggle trace or other debug features of all framework based mods
	private var LocalDebugDV:DistributedValue; // Same as above, only local (Both persist through /reloadui, allowing loadtime traces on mods compiled with them disabled)
}
