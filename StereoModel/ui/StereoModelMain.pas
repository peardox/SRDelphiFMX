//** @abstract(Main form of StereoModel: a Gorilla3D viewport seen through the Spritely
//** orbital camera.)
//**
//** The view is a TSpritelyOrbitalCamera on the form, from the Spritely package, with its
//** headlight on. Once the form is showing it loads the test model, uvcube.glb from the models
//** folder, into the viewport and frames it so it stays in view at every angle.
//**
//** Mouse, on the viewport: a left drag orbits (Azimuth and PolarAngle); a right drag up or
//** down moves the target, the point the camera orbits, deeper or nearer along the line of
//** sight without moving the camera (SetTargetDepth); the wheel brings the view nearer or
//** takes it farther, stopping at the model's nearest face. A click on its own does nothing.
//** Status and problems are shown in the strip at the bottom, logged with FMX's Log.d and
//** written to StereoModel.log (StereoModelLog), beside the executable on Windows.
//**
//** Glasses-free 3D: a TLenticularDisplay, from the Lenticular package, made in code for now.
//** Where the display runtime is installed the Stereo button shows the view woven full screen
//** on the 3D display (TPeardoxGorillaEyes draws the two eyes); where it is not, the button is
//** hidden.
unit StereoModelMain;

{
  Main form of StereoModel: a Gorilla3D viewport seen through the Spritely
  orbital camera.

  The view is a TSpritelyOrbitalCamera on the form, from the Spritely
  package, with its headlight on. Once the form is showing it loads the
  test model, uvcube.glb from the models folder, into the viewport and
  frames it so it stays in view at every angle.

  Mouse, on the viewport: a left drag orbits (Azimuth and PolarAngle); a
  right drag up or down moves the target, the point the camera orbits,
  deeper or nearer along the line of sight without moving the camera
  (SetTargetDepth); the wheel brings the view nearer or takes it farther,
  stopping at the model's nearest face. A click on its own does nothing.
  Status and problems are shown in the strip at the bottom, logged with
  FMX's Log.d and written to StereoModel.log (StereoModelLog), beside the
  executable on Windows.

  Glasses-free 3D: a TLenticularDisplay, from the Lenticular package, made
  in code for now. Where the display runtime is installed the Stereo
  button shows the view woven full screen on the 3D display
  (TPeardoxGorillaEyes draws the two eyes); where it is not, the button is
  hidden.
}

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.Math, System.Math.Vectors, System.IOUtils, System.Generics.Collections,
  FMX.Types, FMX.Types3D, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  Gorilla.Viewport, Gorilla.Camera, Gorilla.Model, Gorilla.Loader, Gorilla.Animation,
  // One unit per model format: each registers its file types with
  // TGorillaLoader when linked in, and File, Open offers what is registered.
  // USD was left out of Sprite3D for a problem in an earlier Gorilla3D, now
  // gone (owner, 7 November 2026). Not here: the Mayo CAD loaders and
  // SketchUp's (external libraries) and Sketchfab's (loads from the web)
  Gorilla.GLB.Loader, Gorilla.GLTF.Loader, Gorilla.OBJ.Loader, Gorilla.FBX.Loader,
  Gorilla.DAE.Loader, Gorilla.STL.Loader, Gorilla.PLY.Loader, Gorilla.USD.Loader,
  Gorilla.Babylon.Loader, Gorilla.G3D.Loader,
  // FMX.Objects (TRectangle) has a TPath of its own, the shape: the file
  // paths below are System.IOUtils.TPath in full
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Menus, FMX.Layouts, FMX.Objects, FMX.ListBox,
  Spritely.OrbitalCamera, Lenticular.Display, Lenticular.Display.Settings, FmxLinuxMenu,
  StereoModelLog, StereoModelEyes, LenticularBridge.Api;

type
  //** @abstract(The main form: the 3D view and the control strip below it.)
  //**
  //** @seealso(TSpritelyOrbitalCamera)
  TForm2 = class(TForm)
    //** @abstract(Holds the view; fills the form above ControlLayout.)
    MainViewLayout: TLayout;
    //** @abstract(The strip of controls along the bottom of the form.)
    ControlLayout: TLayout;
    //** @abstract(The main menu; empty for now.)
    MainMenu1: TMainMenu;
    //** @abstract(The File menu.)
    FileMenuItem: TMenuItem;
    //** @abstract(File, Open: picks a model file and loads it in place of the one shown;
    //** desktop only.)
    OpenMenuItem: TMenuItem;
    //** @abstract(Turns glasses-free 3D on (pressed) and off; hidden where the display runtime is
    //** not installed.)
    btnStereo: TButton;
    //** @abstract(Holds the viewport inside MainViewLayout.)
    ViewLayout: TLayout;
    //** @abstract(The Gorilla3D viewport, seen through SpritelyOrbitalCamera1's camera.)
    GorillaViewport1: TGorillaViewport;
    //** @abstract(The orbital camera, on the form: it makes its camera and headlight in
    //** GorillaViewport1 as the form loads.)
    SpritelyOrbitalCamera1: TSpritelyOrbitalCamera;
    //** @abstract(Makes the status line, reports the orbital camera and hooks up the
    //** viewport's events.)
    //**
    //** @param(Sender The form.)
    procedure FormCreate(Sender: TObject);
    //** @abstract(Queues the test model's load the first time the form is shown, so the
    //** window is drawn first.)
    //**
    //** @param(Sender The form.)
    procedure FormShow(Sender: TObject);
    //** @abstract(File, Open: shows an open dialog for every model format Gorilla3D has a
    //** loader for here, and loads the file chosen.)
    //**
    //** @param(Sender OpenMenuItem.)
    procedure OpenMenuItemClick(Sender: TObject);
    //** @abstract(Stops glasses-free 3D while the window still exists, and closes the log.)
    //**
    //** @param(Sender The form.)
    //**
    //** @param(Action Left as it is: the form closes.)
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    //** @abstract(The Stereo button: starts glasses-free 3D when pressed, stops it when
    //** released, and saves the choice.)
    //**
    //** @param(Sender btnStereo.)
    procedure btnStereoClick(Sender: TObject);
  private
    //** @abstract(The model shown, owned by the viewport; nil until one has loaded.)
    FModel: TGorillaModel;
    //** @abstract(The file FModel came from, for the open dialog's starting folder.)
    FModelPath: string;
    //** @abstract(The status line in the control strip.)
    FStatus: TLabel;
    //** @abstract(The model's animations, left of btnStereo: (none), then each by name, sorted
    //** as Gorilla3D sorts them (as Sprite3D lists them); choosing one plays it, (none) stops
    //** it. Hidden for a model without animations.)
    FAnimationBox: TComboBox;
    //** @abstract(True while FAnimationBox is being filled, so its OnChange does nothing.)
    FFillingAnimations: Boolean;
    //** @abstract(The 3D window: borderless, full screen on the 3D display while Stereo is
    //** on, hidden otherwise. The bridge's window is a child of it, made when the display starts
    //** (with this form hidden), so turning Stereo on is quick.)
    FOutput: TForm;
    //** @abstract(Fills FOutput: FDisplay's Control, so the bridge's window covers it; it takes
    //** the mouse (the bridge's window lets it through) for the same drags and wheel as the
    //** viewport.)
    FOutputHost: TLayout;
    //** @abstract(True while Stereo is on: FOutput shows the woven view.)
    FStereoOn: Boolean;
    //** @abstract(True while this form is hidden for Stereo, as it was on the 3D display.)
    FMainHidden: Boolean;
    //** @abstract(True while the viewport is being resized for Stereo or back: ViewResize then
    //** leaves the view as it is.)
    FResizing: Boolean;
    //** @abstract(FOutput's window when the display last started on it: the bridge's window is its
    //** child. 0 until the display has started.)
    FDisplayParent: NativeUInt;
    //** @abstract(True while the display is being restarted on a new FOutput window: its OnStopped
    //** then leaves Stereo on.)
    FRestarting: Boolean;
    //** @abstract(An opaque cover over the viewport while Stereo is on, with FStereoNote on
    //** it: FMX still draws the viewport (Gorilla3D renders nothing for a hidden one), but
    //** under this, so its camera jumping between the eyes is not seen.)
    FStereoCover: TRectangle;
    //** @abstract(The cover's message.)
    FStereoNote: TLabel;
    //** @abstract(A form that is never seen, shown once off-screen and hidden: the viewport
    //** goes onto it while Stereo is on and this form stays in sight.)
    FRenderForm: TForm;
    //** @abstract(Fires STEREO_WATCH_MS after weaving starts: if nothing has been woven by
    //** then, Stereo is turned off, so a black full-screen window on top cannot trap the user.)
    FStereoWatch: TTimer;
    //** @abstract(Checks every CURSOR_CHECK_MS while Stereo is on whether the mouse pointer is
    //** over the 3D display, and hides it there if the display setting HideCursor says so.)
    FCursorTimer: TTimer;
    //** @abstract(True while this program has the pointer hidden (one ShowCursor(False) to
    //** undo).)
    FCursorHidden: Boolean;
    //** @abstract(True once the test model's load has been queued, so FormShow queues it
    //** only once.)
    FLoadQueued: Boolean;
    //** @abstract(True while a drag is going on: a left one orbits, a right one moves the
    //** target's depth.)
    FDragging: Boolean;
    //** @abstract(True while the drag is a right one: it moves the target's depth instead of
    //** orbiting.)
    FDepthDrag: Boolean;
    //** @abstract(The mouse position at the last step of the drag, in viewport coordinates.)
    FDragLast: TPointF;
    //** @abstract(How far the wheel has zoomed from the fitted view: 1 is the fit, below 1
    //** nearer; kept between ZOOM_MIN and ZOOM_MAX.)
    FZoom: Single;
    //** @abstract(Glasses-free 3D: the TLenticularDisplay for GorillaViewport1, made in code for
    //** now; owned by the form.)
    FDisplay: TLenticularDisplay;
    //** @abstract(First light: draws GorillaViewport1 once per eye through
    //** SpritelyOrbitalCamera1 and hands the pair to FDisplay, while it runs.)
    FEyes: TPeardoxGorillaEyes;
    //** @abstract(Shows a line in the status strip, and logs it with Log.d and in
    //** StereoModel.log.)
    //**
    //** @param(AText The line.)
    procedure ShowStatus(const AText: string);
    //** @abstract(Finds the test model in the places it can be on each platform.)
    //**
    //** Looks in a models folder beside the executable (a deployed Windows or Linux build), in
    //** the bundle's Resources (macOS), in the documents folder (Android and iOS, where
    //** System.StartUpCopy puts deployed files), then in each folder above the executable, which
    //** finds the repository's models folder when run from the IDE's output folder.
    //**
    //** @param(ATried Set to the folders looked in, for the message when it is not found.)
    //**
    //** @returns(The model's full path, or an empty string if it is in none of them.)
    function FindTestModel(out ATried: string): string;
    //** @abstract(Finds the test model and loads it; see LoadModel.)
    procedure LoadTestModel;
    //** @abstract(Puts the camera at the test scene's view: TEST_VIEW_AZIMUTH,
    //** TEST_VIEW_INCLINATION and TEST_VIEW_ROLL, framed, then TEST_VIEW_DEPTH from the
    //** target.)
    procedure TestView;
    //** @abstract(Runs once the form is first showing: loads the test model, then starts the
    //** display (not Stereo) if the display runtime is installed, so btnStereo is ready.)
    procedure FirstShown;
    //** @abstract(Makes FDisplay, hooks up its events and shows or hides btnStereo.)
    procedure CreateDisplay;
    //** @abstract(FDisplay's log: every line to the status strip and Log.d.)
    //**
    //** @param(Sender FDisplay.)
    //**
    //** @param(AText The line.)
    procedure DisplayLog(Sender: TObject; const AText: string);
    //** @abstract(FDisplay has started (on the hidden FOutput): btnStereo is enabled.)
    //**
    //** @param(Sender FDisplay.)
    procedure DisplayStarted(Sender: TObject);
    //** @abstract(FDisplay has stopped: Stereo off, btnStereo disabled.)
    //**
    //** @param(Sender FDisplay.)
    procedure DisplayStopped(Sender: TObject);
    //** @abstract(Glasses-free 3D could not start: btnStereo stays disabled and the reason
    //** goes to the status strip.)
    //**
    //** @param(Sender FDisplay.)
    //**
    //** @param(AProblem What went wrong.)
    //**
    //** @param(AMessage The details.)
    procedure DisplayProblem(Sender: TObject; AProblem: TLenticularDisplayProblem;
      const AMessage: string);
    //** @abstract(Makes FOutput and FOutputHost, hidden.)
    procedure CreateOutput;
    //** @abstract(Fills FAnimationBox from FModel's animations and plays the first, or hides
    //** it for a model without any.)
    procedure FillAnimations;
    //** @abstract(FAnimationBox OnChange: plays the animation chosen, or stops it for (none).)
    //**
    //** @param(Sender FAnimationBox.)
    procedure AnimationBoxChange(Sender: TObject);
    //** @abstract(Turns Stereo on: FOutput full screen on the 3D display, the viewport at the
    //** display's recommended view size, this form hidden if it is on the 3D display, and the
    //** two eyes woven (the lens comes on).)
    //**
    //** @returns(True if Stereo is on.)
    function EnterStereo: Boolean;
    //** @abstract(Turns Stereo off: weaving stops (the lens goes off), FOutput is hidden, the
    //** viewport fills its layout again and this form shows again if it was hidden. The display
    //** keeps running, for the next time.)
    procedure LeaveStereo;
    //** @abstract(Puts FOutput over the whole 3D display, on top, and logs where it went.)
    //**
    //** @param(ARect The 3D display, in desktop pixels.)
    procedure PlaceOutput(const ARect: TRect);
    //** @abstract(Sizes the viewport for Stereo (the display's recommended view, in physical
    //** pixels, centred in ViewLayout and clipped) or back to filling ViewLayout.)
    //**
    //** @param(AOn True for Stereo.)
    procedure SizeViewForStereo(AOn: Boolean);
    //** @abstract(FOutput OnClose (Alt+F4 on it): Stereo off, and the form only hidden.)
    //**
    //** @param(Sender FOutput.)
    //**
    //** @param(Action Set to caHide.)
    procedure OutputClose(Sender: TObject; var Action: TCloseAction);
    //** @abstract(FStereoWatch OnTimer: Stereo off if no frame has been woven.)
    //**
    //** @param(Sender FStereoWatch.)
    procedure StereoWatchTimer(Sender: TObject);
    //** @abstract(Starts the eyes and FStereoWatch.)
    procedure StartWeaving;
    //** @abstract(FCursorTimer OnTimer: the pointer hidden while it is over the 3D display in
    //** Stereo and HideCursor is set, shown otherwise.)
    //**
    //** @param(Sender FCursorTimer.)
    procedure CursorTimer(Sender: TObject);
    //** @abstract(Hides or shows the mouse pointer, once each way (Windows' ShowCursor keeps a
    //** count).)
    //**
    //** @param(AHide True to hide it.)
    procedure SetCursorHidden(AHide: Boolean);
    //** @abstract(FEyes' log: every line to the status strip and the log file.)
    //**
    //** @param(Sender FEyes.)
    //**
    //** @param(AText The line.)
    procedure EyesLog(Sender: TObject; const AText: string);
    //** @abstract(The keys for glasses-free 3D, acted on once a press however long it is
    //** held: L steps the weaver's latency (0 to LATENCY_MAX_FRAMES), [ and ] the eye
    //** separation by EYE_SEPARATION_STEP_MM, C turns the bridge's frame cap off and on (the
    //** wait for the 3D display's vertical blank after each frame; off by default), V the
    //** per-eye view (off: full speed), comma and full stop the render scale down and up by
    //** RENDER_SCALE_STEP, M hiding the mouse pointer over the 3D display, W weaving (off: one
    //** flat view, lens off, for screen recordings) - all saved -, Home puts the view back
    //** (the test view for the test scene), P logs a snapshot
    //** of everything that sets the view (as LenticularDemoFMX's P does), Esc turns Stereo off
    //** (while it is on).)
    //**
    //** @param(Sender The form.)
    //**
    //** @param(Key The key's code.)
    //**
    //** @param(KeyChar The character, if any.)
    //**
    //** @param(Shift The keys and buttons held.)
    {$IFNDEF MSWINDOWS}
    procedure FormKeyUp(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    {$ENDIF}
    //** @abstract(Does what a key does (the keys are listed at FormKeyUp's comment and in
    //** IsTestKey).)
    //**
    //** @param(AKey The key's virtual key code.)
    procedure HandleKey(AKey: Word);
    //** @abstract(True for the keys HandleKey acts on.)
    //**
    //** @param(AKey The key's virtual key code.)
    //**
    //** @returns(True for L, [, ], P, Home, C, V, comma, full stop, M and W.)
    class function IsTestKey(AKey: Word): Boolean; static;
    //** @abstract(Loads a model file into the viewport in place of the one shown, stands it
    //** upright and frames it.)
    //**
    //** Gorilla3D picks the loader by the file's extension. The new model is made and loaded
    //** first (TGorillaModel.LoadFromFile into a model of our own, not
    //** TGorillaModel.LoadNewModelFromFile, which leaks the FBX loader's parse tree) and the
    //** old one freed only once it has loaded, so a file that fails leaves the view as it
    //** was. The new model becomes the camera's Subject.
    //**
    //** @param(APath The model file, with its full path.)
    //**
    //** @returns(True if it loaded; False, with the reason in the status line, otherwise.)
    function LoadModel(const APath: string): Boolean;
    //** @abstract(Builds the open dialog's filter from the file types Gorilla3D's loaders have
    //** registered.)
    //**
    //** TGorillaLoader.FileTypes holds one entry per extension a linked-in loader opens, so the
    //** filter offers exactly what can be loaded: all of them together first, then each on its
    //** own, then all files.
    //**
    //** @returns(The filter, in TOpenDialog's "description|pattern|..." form.)
    function ModelFilter: string;
    //** @abstract(Centres the model on its bounds and turns it upright, as Sprite3D's
    //** PlaceModel does.)
    //**
    //** glTF's up is +Y and FMX's is -Y, so a model comes in upside down until it is turned
    //** MODEL_TURN_X degrees about X.
    procedure PlaceModel;
    //** @abstract(Frames the model for every angle, then puts the wheel's zoom back on top.)
    procedure FitView;
    //** @abstract(Puts the starting view back: all three angles 0, the fitted size.)
    procedure ResetView;
    //** @abstract(The status line for a right drag: the target's depth, and where the model
    //** lies against the glass.)
    //**
    //** The target's depth is the plane that will lie on the display's glass. The model's
    //** centre, measured along the line of sight, is then that much in front of the glass
    //** (out of the screen, Z below 0) or behind it (Z above 0): Z = model depth - target
    //** depth. While the display runs it is also given in millimetres, at the scale that puts the
    //** view's height in the camera's field of view at the target's depth onto the view's height
    //** on the display.
    //**
    //** @returns(The line.)
    function DepthStatus: string;
    //** @abstract(The model centre's depth along the line of sight from the camera.)
    //**
    //** @param(ADepth Set to the depth, scene units.)
    //**
    //** @returns(False while there is no model or camera.)
    function ModelDepth(out ADepth: Single): Boolean;
    //** @abstract(The view as numbers, to note down for a test scene: the camera's azimuth,
    //** inclination (PolarAngle: 0 level, +90 above looking down) and roll in degrees, the
    //** target depth, and the model centre's Z against the glass (below 0: in front).)
    //**
    //** @returns(The line.)
    function ViewText: string;
    //** @abstract(Shows ViewText in the form's caption, so the angles stay in view while the
    //** status line shows other things.)
    procedure ShowView;
    //** @abstract(Viewport OnResize: refits, as the fit depends on the view's shape.)
    //**
    //** @param(Sender The viewport.)
    procedure ViewResize(Sender: TObject);
    //** @abstract(Viewport OnMouseDown: a left press starts orbiting, a right press starts
    //** moving the target's depth.)
    //**
    //** @param(Sender The viewport.)
    //**
    //** @param(Button The button pressed.)
    //**
    //** @param(Shift The keys and buttons held.)
    //**
    //** @param(X The mouse position across the viewport.)
    //**
    //** @param(Y The mouse position down the viewport.)
    procedure ViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    //** @abstract(Viewport OnMouseMove: orbits the camera while the left button is held, or
    //** moves the target's depth while the right one is.)
    //**
    //** @param(Sender The viewport.)
    //**
    //** @param(Shift The keys and buttons held.)
    //**
    //** @param(X The mouse position across the viewport.)
    //**
    //** @param(Y The mouse position down the viewport.)
    procedure ViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    //** @abstract(Viewport OnMouseUp: letting go of the button that started the drag ends it.)
    //**
    //** @param(Sender The viewport.)
    //**
    //** @param(Button The button let go.)
    //**
    //** @param(Shift The keys and buttons held.)
    //**
    //** @param(X The mouse position across the viewport.)
    //**
    //** @param(Y The mouse position down the viewport.)
    procedure ViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    //** @abstract(Viewport OnMouseWheel: brings the view nearer or takes it farther.)
    //**
    //** In perspective each notch moves the camera along its line of sight by a share of its
    //** distance from the model, so the steps stay the same size wherever the target's depth
    //** has been put; orthographic views are scaled instead.
    //**
    //** @param(Sender The viewport.)
    //**
    //** @param(Shift The keys and buttons held.)
    //**
    //** @param(WheelDelta How far the wheel turned; WHEEL_NOTCH a notch, positive away from the
    //** user.)
    //**
    //** @param(Handled Set to True, so the form does not scroll as well.)
    procedure ViewMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      var Handled: Boolean);
  public
    //** @abstract(Called by the keyboard hook (Windows) for each key going down in this
    //** thread, before FMX or the bridge's window sees it.)
    //**
    //** Only while this form is the active window (not while a dialog is up), and only for the
    //** test keys: HandleKey is queued for a first press, a held key's repeats are dropped.
    //**
    //** @param(AKey The virtual key code.)
    //**
    //** @param(AIsRepeat True for an auto-repeat.)
    //**
    //** @returns(True if the key was a test key, so it must not go further.)
    function HookKey(AKey: Word; AIsRepeat: Boolean): Boolean;
  end;

var
  //** @abstract(The main form, made by the .dpr.)
  Form2: TForm2;

implementation

{$R *.fmx}

{$IFDEF MSWINDOWS}
uses
  FMX.Platform.Win;

// The few Windows calls the keyboard hook needs, declared here as LenticularDemoFMX
// does, rather than using Winapi.Windows, whose names (TBitmap and others)
// would hide FMX's in this unit
const
  //** @abstract(SetWindowsHookEx: hook keyboard messages.)
  WH_KEYBOARD = 2;
  //** @abstract(Hook code: a key message is being taken from the queue.)
  HC_ACTION = 0;

function SetWindowsHookExW(idHook: Integer; lpfn: Pointer; hmod: NativeUInt;
  dwThreadId: Cardinal): NativeUInt; stdcall; external 'user32.dll';
function UnhookWindowsHookEx(hhk: NativeUInt): LongBool; stdcall; external 'user32.dll';
function CallNextHookEx(hhk: NativeUInt; nCode: Integer; wParam: NativeUInt;
  lParam: NativeInt): NativeInt; stdcall; external 'user32.dll';
function GetActiveWindow: NativeUInt; stdcall; external 'user32.dll';
function GetWindowRect(hWnd: NativeUInt; out lpRect: TRect): LongBool; stdcall;
  external 'user32.dll';
function SetWindowPos(hWnd, hWndInsertAfter: NativeUInt; X, Y, cx, cy: Integer;
  uFlags: Cardinal): LongBool; stdcall; external 'user32.dll';

const
  //** @abstract(SetWindowPos: above every window that is not topmost (HWND(-1)).)
  HWND_TOPMOST = High(NativeUInt);
  //** @abstract(SetWindowPos: show the window.)
  SWP_SHOWWINDOW = $0040;
  //** @abstract(GetWindow: the first child.)
  GW_CHILD = 5;
  //** @abstract(GetWindow: the next window at the same level.)
  GW_HWNDNEXT = 2;
  //** @abstract(Window message: which part of the window the pointer is over.)
  WM_NCHITTEST = $0084;
  //** @abstract(Window message: the window's last.)
  WM_NCDESTROY = $0082;
  //** @abstract(WM_NCHITTEST answer: look at the window underneath, in the same thread.)
  HTTRANSPARENT = -1;
  //** @abstract(The id PassMouseThrough is installed under.)
  PASS_MOUSE_SUBCLASS_ID = 1;
function ShowCursor(bShow: LongBool): Integer; stdcall; external 'user32.dll';
function GetWindow(hWnd: NativeUInt; uCmd: Cardinal): NativeUInt; stdcall; external 'user32.dll';
function SetWindowSubclass(hWnd: NativeUInt; pfnSubclass: Pointer; uIdSubclass,
  dwRefData: NativeUInt): LongBool; stdcall; external 'comctl32.dll';
function RemoveWindowSubclass(hWnd: NativeUInt; pfnSubclass: Pointer;
  uIdSubclass: NativeUInt): LongBool; stdcall; external 'comctl32.dll';
function DefSubclassProc(hWnd: NativeUInt; uMsg: Cardinal; wParam: NativeUInt;
  lParam: NativeInt): NativeInt; stdcall; external 'comctl32.dll';
function GetCursorPos(out lpPoint: TPoint): LongBool; stdcall; external 'user32.dll';
function GetCurrentThreadId: Cardinal; stdcall; external 'kernel32.dll';
function GetLastError: Cardinal; stdcall; external 'kernel32.dll';
{$ENDIF}

var
  //** @abstract(The keyboard hook, 0 if none.)
  KeyHook: NativeUInt = 0;
  //** @abstract(The form the hook reports to, nil once it is gone.)
  KeyHookForm: TForm2 = nil;

{$IFDEF MSWINDOWS}
//** @abstract(Thread keyboard hook: sees every key message this thread takes from its queue,
//** before FMX or any native child window (the bridge's) does.)
//**
//** @param(Code The hook code.)
//**
//** @param(WParam The virtual key.)
//**
//** @param(LParam Repeat count and flags: bit 31 set on key up, bit 30 on a repeat.)
//**
//** @returns(1 to swallow the key, otherwise the next hook's result.)
function KeyHookProc(Code: Integer; WParam: NativeUInt; LParam: NativeInt): NativeInt; stdcall;
begin
  if (Code = HC_ACTION) and (KeyHookForm <> nil) and ((LParam and $80000000) = 0) then
    if KeyHookForm.HookKey(Word(WParam), (LParam and $40000000) <> 0) then
      Exit(1);
  Result := CallNextHookEx(KeyHook, Code, WParam, LParam);
end;

//** @abstract(Window subclass for the bridge's child window: the mouse passes through it to
//** the 3D window underneath, so drags and the wheel reach FMX while Stereo is on (owner, 22:59:
//** "right click + drag still doesn't work" - the bridge's window covers the view and took
//** every mouse message).)
//**
//** @param(hWnd The bridge's window.)
//**
//** @param(uMsg The message.)
//**
//** @param(wParam Its first parameter.)
//**
//** @param(lParam Its second parameter.)
//**
//** @param(uIdSubclass PASS_MOUSE_SUBCLASS_ID.)
//**
//** @param(dwRefData Not used.)
//**
//** @returns(HTTRANSPARENT for WM_NCHITTEST, otherwise what the window itself answers.)
function PassMouseThrough(hWnd: NativeUInt; uMsg: Cardinal; wParam: NativeUInt;
  lParam: NativeInt; uIdSubclass, dwRefData: NativeUInt): NativeInt; stdcall;
begin
  if uMsg = WM_NCHITTEST then
    Exit(HTTRANSPARENT);
  if uMsg = WM_NCDESTROY then
    RemoveWindowSubclass(hWnd, @PassMouseThrough, PASS_MOUSE_SUBCLASS_ID);
  Result := DefSubclassProc(hWnd, uMsg, wParam, lParam);
end;

//** @abstract(Installs the keyboard hook for this thread, reporting to AForm.)
//**
//** @param(AForm The form whose HookKey sees the keys.)
procedure InstallKeyHook(AForm: TForm2);
begin
  KeyHookForm := AForm;
  KeyHook := SetWindowsHookExW(WH_KEYBOARD, @KeyHookProc, 0, GetCurrentThreadId);
  if KeyHook = 0 then
    LogLine(Format('Keyboard hook NOT installed (error %d): the test keys will not work',
      [GetLastError]))
  else
    LogLine('Keyboard hook installed: L [ ] C V , . M W P Home Esc');
end;

//** @abstract(Removes the keyboard hook; the form no longer sees keys.)
procedure RemoveKeyHook;
begin
  KeyHookForm := nil;
  if KeyHook <> 0 then
    UnhookWindowsHookEx(KeyHook);
  KeyHook := 0;
end;
{$ENDIF}

const
  //** @abstract(The folder the test models are in, beside the executable or at the
  //** repository's root.)
  MODEL_FOLDER = 'models';
  //** @abstract(The model loaded at start: LenticularDemoFMX's scene without its back wall
  //** (owner, 7 November 2026: the definitive test scene), seen from TEST_VIEW_AZIMUTH and
  //** the rest.)
  TEST_MODEL = 'DemoSceneNoWall.glb';
  //** @abstract(The test scene's view: the camera's azimuth, degrees (owner, 7 November 2026,
  //** found by eye on the 3D display: "the 3D really pops out").)
  TEST_VIEW_AZIMUTH = 52;
  //** @abstract(The test scene's view: the inclination (PolarAngle), degrees.)
  TEST_VIEW_INCLINATION = 75;
  //** @abstract(The test scene's view: the roll, degrees.)
  TEST_VIEW_ROLL = 0;
  //** @abstract(The test scene's view: the target depth, scene units (the camera this far
  //** from the target, which the fit puts on the model's turning axis).)
  TEST_VIEW_DEPTH = 42;
  //** @abstract(Millimetres the [ and ] keys change the eye separation by.)
  EYE_SEPARATION_STEP_MM = 5;
  //** @abstract(How often FCursorTimer checks where the mouse pointer is, ms.)
  CURSOR_CHECK_MS = 100;
  //** @abstract(The step the , and . keys change the render scale by.)
  RENDER_SCALE_STEP = 0.25;
  //** @abstract(The smallest eye separation the keys go to, millimetres.)
  EYE_SEPARATION_MIN_MM = 20;
  //** @abstract(The largest eye separation the keys go to, millimetres.)
  EYE_SEPARATION_MAX_MM = 90;
  //** @abstract(The largest weaver latency the L key cycles to, frames.)
  LATENCY_MAX_FRAMES = 4;
  //** @abstract(How many folders above the executable FindTestModel looks in for MODEL_FOLDER.)
  FOLDERS_UP = 6;
  //** @abstract(The turn about X, in degrees, that stands a loaded model upright, as
  //** Sprite3D's MODEL_ROTATION does: glTF's up is +Y, FMX's is -Y.)
  MODEL_TURN_X = 180;
  //** @abstract(The open dialog's first entry: every model type together; Format arguments
  //** are the pattern list, twice.)
  MODEL_FILTER_ALL = 'All models (%s)|%s';
  //** @abstract(One model type's entry in the open dialog; Format arguments are its name and
  //** its extension, twice.)
  MODEL_FILTER_ONE = '|%s (*.%s)|*.%s';
  //** @abstract(The open dialog's last entry.)
  MODEL_FILTER_ANY = '|All files (*.*)|*.*';
  //** @abstract(Padding round the model as a fraction of the view, as in VirtualGamepad.)
  VIEW_MARGIN = 0.08;
  //** @abstract(Factor the target's depth changes by per pixel of a right drag up: deeper
  //** going up, nearer going down, in proportion, so it suits any scale.)
  DEPTH_STEP_PER_PIXEL = 1.01;
  //** @abstract(Degrees the camera orbits per pixel of mouse movement, as in Sprite3D.)
  ORBIT_DEGREES_PER_PIXEL = 0.5;
  //** @abstract(Zoom factor per wheel notch: rolling away brings the view nearer.)
  ZOOM_STEP = 1.1;
  //** @abstract(The nearest the wheel can bring the view, as a fraction of the fit.)
  ZOOM_MIN = 0.2;
  //** @abstract(The farthest the wheel can take the view, as a multiple of the fit.)
  ZOOM_MAX = 10.0;
  //** @abstract(The nearest the wheel takes the camera to the target, as a share of its
  //** distance before the notch, when the target is in front of the model.)
  MIN_TARGET_SHARE = 0.05;
  //** @abstract(The wheel delta of one notch.)
  WHEEL_NOTCH = 120;
  //** @abstract(Room at the right of the control strip kept for btnStereo.)
  STATUS_RIGHT_MARGIN = 96;
  //** @abstract(FAnimationBox's width, in pixels.)
  ANIMATION_BOX_WIDTH = 180;
  //** @abstract(FAnimationBox's first entry: no animation playing.)
  NO_ANIMATION = '(none)';
  //** @abstract(How long after weaving starts the first frame must have been woven, ms.)
  STEREO_WATCH_MS = 3000;
  //** @abstract(Gap at the status line's left, in pixels.)
  STATUS_LEFT_MARGIN = 8;

procedure TForm2.FormCreate(Sender: TObject);
begin
  // The log first, so it has everything
  LogOpen;
  // Then: on desktop Linux the main menu is moved onto an FMX menu bar,
  // as GTK's native bar shows only first letters (FmxLinuxMenu, from
  // TSteamAPI); it does nothing elsewhere
  ReplaceMainMenu(Self, MainMenu1);
  {$IF DEFINED(ANDROID) or DEFINED(IOS)}
  // FMX's open dialog is desktop only
  FileMenuItem.Visible := False;
  {$ENDIF}
  FZoom := 1;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := ControlLayout;
  FStatus.Align := TAlignLayout.Client;
  FStatus.Margins.Left := STATUS_LEFT_MARGIN;
  FStatus.Margins.Right := STATUS_RIGHT_MARGIN;
  // Right of the status line, left of btnStereo (owner, 20:20: a way to
  // choose the animation, as Sprite3D has)
  FAnimationBox := TComboBox.Create(Self);
  FAnimationBox.Parent := ControlLayout;
  FAnimationBox.Align := TAlignLayout.Right;
  FAnimationBox.Width := ANIMATION_BOX_WIDTH;
  FAnimationBox.Margins.Top := 7;
  FAnimationBox.Margins.Bottom := 7;
  FAnimationBox.Margins.Right := STATUS_RIGHT_MARGIN;
  FAnimationBox.Visible := False;
  FAnimationBox.OnChange := AnimationBoxChange;
  FStatus.WordWrap := False;
  // Owner (19:43): with Stereo in its own window the lens indicator told
  // nothing: the lens is on exactly while Stereo is
  // The component is on the form: by now it has made its camera, and its
  // headlight, in the viewport, as the form loaded
  if SpritelyOrbitalCamera1.Camera = nil then
    ShowStatus('Orbital camera NOT made: no camera in the viewport')
  else
    ShowStatus(Format('Orbital camera made: FOV %.0f, distance %.2f, headlight %s',
      [SpritelyOrbitalCamera1.FOV, SpritelyOrbitalCamera1.Distance,
       BoolToStr(SpritelyOrbitalCamera1.Light <> nil, True)]));
  GorillaViewport1.OnResize := ViewResize;
  GorillaViewport1.OnMouseDown := ViewMouseDown;
  GorillaViewport1.OnMouseMove := ViewMouseMove;
  GorillaViewport1.OnMouseUp := ViewMouseUp;
  GorillaViewport1.OnMouseWheel := ViewMouseWheel;
  CreateOutput;
  CreateDisplay;
end;

procedure TForm2.CreateDisplay;
begin
  // Made in code for now (owner, 7 November 2026); a component on the form
  // later
  FDisplay := TLenticularDisplay.Create(Self);
  // The bridge's window goes on the full-screen form (owner, 19:43)
  FDisplay.Control := FOutputHost;
  FDisplay.OnLog := DisplayLog;
  FDisplay.OnStarted := DisplayStarted;
  FDisplay.OnStopped := DisplayStopped;
  FDisplay.OnProblem := DisplayProblem;
  // First light: the two eyes drawn while the display runs
  FEyes := TPeardoxGorillaEyes.Create(Self);
  FEyes.Display := FDisplay;
  FEyes.Camera := SpritelyOrbitalCamera1;
  FEyes.Viewport := GorillaViewport1;
  FEyes.OnLog := EyesLog;
  // Windows: a thread keyboard hook, as LenticularDemoFMX's. FMX never passed the
  // key-ups to OnKeyUp here (owner, 19:21: C pressed twice, nothing logged;
  // no key line, P included, since the change to key-up at 17:58). The hook
  // drops a held key's repeats, which had toggled again and again on
  // key-down (owner, 17:58)
  {$IFDEF MSWINDOWS}
  InstallKeyHook(Self);
  {$ELSE}
  OnKeyUp := FormKeyUp;
  {$ENDIF}
  ShowStatus(FDisplay.SettingsStatus);
  // No display runtime here: nothing about glasses-free 3D is shown
  btnStereo.Visible := TLenticularDisplay.Installed;
  btnStereo.IsPressed := False;
  // Until the display has started (owner, 19:43: disabled until the display is available, so
  // that switching is quick)
  btnStereo.Enabled := False;
  if not btnStereo.Visible then
    ShowStatus('Glasses-free 3D not installed (or not a Windows 64-bit build): Stereo hidden')
  else
    ShowStatus('Glasses-free 3D installed; Stereo is enabled once the display has started');
end;

procedure TForm2.CreateOutput;
begin
  FOutput := TForm.CreateNew(Self);
  FOutput.Caption := 'StereoModel 3D';
  FOutput.BorderStyle := TFmxFormBorderStyle.None;
  FOutput.Fill.Kind := TBrushKind.Solid;
  FOutput.Fill.Color := TAlphaColors.Black;
  FOutput.OnClose := OutputClose;
  FOutputHost := TLayout.Create(FOutput);
  FOutputHost.Parent := FOutput;
  FOutputHost.Align := TAlignLayout.Client;
  FOutputHost.HitTest := True;
  FOutputHost.OnMouseDown := ViewMouseDown;
  FOutputHost.OnMouseMove := ViewMouseMove;
  FOutputHost.OnMouseUp := ViewMouseUp;
  FOutputHost.OnMouseWheel := ViewMouseWheel;
  FRenderForm := TForm.CreateNew(Self);
  FRenderForm.Caption := 'StereoModel render';
  FRenderForm.BorderStyle := TFmxFormBorderStyle.None;
  FStereoCover := TRectangle.Create(Self);
  FStereoCover.Parent := ViewLayout;
  FStereoCover.Align := TAlignLayout.Contents;
  FStereoCover.Fill.Kind := TBrushKind.Solid;
  FStereoCover.Fill.Color := $FF202428;
  FStereoCover.Stroke.Kind := TBrushKind.None;
  // Drags and the wheel on the cover work on the view too, so the launcher
  // can move the view while Stereo shows it on the 3D display
  FStereoCover.HitTest := True;
  FStereoCover.OnMouseDown := ViewMouseDown;
  FStereoCover.OnMouseMove := ViewMouseMove;
  FStereoCover.OnMouseUp := ViewMouseUp;
  FStereoCover.OnMouseWheel := ViewMouseWheel;
  FStereoCover.Visible := False;
  FStereoNote := TLabel.Create(Self);
  FStereoNote.Parent := FStereoCover;
  FStereoNote.Align := TAlignLayout.Client;
  FStereoNote.TextSettings.HorzAlign := TTextAlign.Center;
  FStereoNote.TextSettings.VertAlign := TTextAlign.Center;
  FStereoNote.Text := 'Showing in glasses-free 3D on the 3D display' + sLineBreak +
    'Esc or Stereo turns it off';
  FStereoNote.StyledSettings := FStereoNote.StyledSettings - [TStyledSetting.FontColor];
  FStereoNote.TextSettings.FontColor := TAlphaColors.White;
  FStereoWatch := TTimer.Create(Self);
  FStereoWatch.Enabled := False;
  FStereoWatch.Interval := STEREO_WATCH_MS;
  FStereoWatch.OnTimer := StereoWatchTimer;
  FCursorTimer := TTimer.Create(Self);
  FCursorTimer.Enabled := False;
  FCursorTimer.Interval := CURSOR_CHECK_MS;
  FCursorTimer.OnTimer := CursorTimer;
end;

procedure TForm2.FillAnimations;
var
  Anims: TArray<TGorillaAnimation>;
  A: TGorillaAnimation;
begin
  FFillingAnimations := True;
  try
    FAnimationBox.Items.Clear;
    Anims := nil;
    if (FModel <> nil) and (FModel.AnimationManager <> nil) then
      try
        Anims := FModel.AnimationManager.GetSortedAnimations();
      except
        on E: Exception do
          ShowStatus(Format('Animations NOT listed: %s: %s', [E.ClassName, E.Message]));
      end;
    if Length(Anims) = 0 then
    begin
      FAnimationBox.Visible := False;
      FStatus.Margins.Right := STATUS_RIGHT_MARGIN;
      ShowStatus('No animation in this model');
      Exit;
    end;
    FAnimationBox.Items.Add(NO_ANIMATION);
    for A in Anims do
      FAnimationBox.Items.Add(A.Id);
    FAnimationBox.Visible := True;
    // The box keeps btnStereo's room; the status line stops at the box
    FStatus.Margins.Right := STATUS_LEFT_MARGIN;
    FAnimationBox.ItemIndex := 1;
    ShowStatus(Format('%d animation(s): %s', [Length(Anims),
      string.Join(', ', Copy(FAnimationBox.Items.ToStringArray, 1, Length(Anims)))]));
  finally
    FFillingAnimations := False;
  end;
  AnimationBoxChange(FAnimationBox);
end;

procedure TForm2.AnimationBoxChange(Sender: TObject);
var
  Id: string;
  Current: TGorillaAnimation;
begin
  if FFillingAnimations or (FModel = nil) or (FModel.AnimationManager = nil) then
    Exit;
  try
    if FAnimationBox.ItemIndex <= 0 then
    begin
      Current := FModel.AnimationManager.Current;
      if Current <> nil then
        Current.Stop;
      ShowStatus('Animation stopped');
      Exit;
    end;
    Id := FAnimationBox.Items[FAnimationBox.ItemIndex];
    if FModel.AnimationManager.PlayAnimation(Id) <> nil then
      ShowStatus('Animation playing: ' + Id)
    else
      ShowStatus('Animation NOT found: ' + Id);
  except
    on E: Exception do
      ShowStatus(Format('Animation NOT played: %s: %s', [E.ClassName, E.Message]));
  end;
end;

procedure TForm2.StartWeaving;
begin
  FEyes.Start;
  FStereoWatch.Enabled := False;
  FStereoWatch.Enabled := True;
end;

procedure TForm2.StereoWatchTimer(Sender: TObject);
begin
  FStereoWatch.Enabled := False;
  if FStereoOn and (FEyes.WovenFrames = 0) then
  begin
    ShowStatus(Format('Nothing woven %d ms after Stereo came on: Stereo turned off',
      [STEREO_WATCH_MS]));
    LeaveStereo;
  end;
end;

procedure TForm2.FirstShown;
begin
  LoadTestModel;
  // The display starts now, on the hidden 3D window, with the lens off: Stereo then
  // only shows it (owner, 19:43: "The window should start Lens Off").
  // Settings.UseGlassesFree3D is not used here
  if TLenticularDisplay.Installed then
  begin
    // FMX makes the 3D window's window again the first time it is shown
    // (owner, 19:58 and 19:59: $551040 then $561040, $CF1004 then $D01004),
    // which took the bridge's window with it: show it once now, out of
    // sight, so the display starts on the window it will keep
    FOutput.SetBounds(-32000, -32000, 64, 64);
    FOutput.Show;
    FOutput.Hide;
    // The same for the render form, so its window is the one it keeps
    FRenderForm.SetBounds(-32000, -32000, 64, 64);
    FRenderForm.Show;
    FRenderForm.Hide;
    Activate;
    FDisplay.Start;
  end;
end;

procedure TForm2.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // While FOutput's window, the parent of the bridge's, still exists
  LeaveStereo;
  FEyes.Stop;
  // While the viewport's OpenGL context still exists
  FEyes.ReleaseZeroCopy;
  FDisplay.Stop;
  {$IFDEF MSWINDOWS}
  RemoveKeyHook;
  {$ENDIF}
  LogClose;
end;

procedure TForm2.btnStereoClick(Sender: TObject);
begin
  if btnStereo.IsPressed then
  begin
    if not EnterStereo then
      btnStereo.IsPressed := False;
  end
  else
    LeaveStereo;
end;

function TForm2.EnterStereo: Boolean;
var
  R: TRect;
  Where: string;
  {$IFDEF MSWINDOWS}
  M: TRect;
  {$ENDIF}
begin
  Result := FStereoOn;
  if FStereoOn then
    Exit;
  if not FDisplay.Running then
  begin
    ShowStatus('Stereo: the display is not running');
    Exit;
  end;
  if not FDisplay.DisplayRect(R) or R.IsEmpty then
  begin
    ShowStatus('Stereo: where the 3D display is on the desktop is not known');
    Exit;
  end;
  // On the 3D display this form would be under the 3D window, blurred by
  // the lens: hidden until Stereo is off. Elsewhere it stays (owner, 19:43)
  FMainHidden := False;
  {$IFDEF MSWINDOWS}
  if GetWindowRect(FormToHWND(Self), M) then
    FMainHidden := R.Contains(M.CenterPoint);
  {$ENDIF}
  SizeViewForStereo(True);
  FOutput.Show;
  PlaceOutput(R);
  if FMainHidden then
    Hide;
  FStereoOn := True;
  btnStereo.IsPressed := True;
  FCursorTimer.Enabled := True;
  {$IFDEF MSWINDOWS}
  // Owner (19:53): black, and the bridge's window measured 0 x 0 mm at the
  // panel's corner, as a window that no longer exists would: FMX had made
  // the 3D window's window again when it was first shown, taking the
  // bridge's (its child) with it. The display is then started again on the new one
  // (about a third of a second in Release); the Eyes start once it has
  ShowStatus(Format('3D window: window $%x now, the display started on $%x',
    [FormToHWND(FOutput), FDisplayParent]));
  if FormToHWND(FOutput) <> FDisplayParent then
  begin
    ShowStatus('The 3D window''s window was made again since the display started on it: ' +
      'starting the display again on the new one');
    FRestarting := True;
    try
      FDisplay.Stop;
    finally
      FRestarting := False;
    end;
    btnStereo.Enabled := False;
    if not FDisplay.Start then
      LeaveStereo;
    Exit(FStereoOn);
  end;
  {$ENDIF}
  if FMainHidden then
    Where := 'hidden (it was on the 3D display)'
  else
    Where := 'stays where it is';
  ShowStatus(Format('Stereo on: full screen on %s at (%d, %d) %d x %d; this window %s; ' +
    'Esc or Stereo turns it off', [FDisplay.DisplayName, R.Left, R.Top, R.Width, R.Height,
    Where]));
  StartWeaving;
  Result := True;
end;

procedure TForm2.SetCursorHidden(AHide: Boolean);
begin
  if AHide = FCursorHidden then
    Exit;
  FCursorHidden := AHide;
  {$IFDEF MSWINDOWS}
  // Over this thread's windows, the bridge's child window included
  ShowCursor(not AHide);
  {$ENDIF}
end;

procedure TForm2.CursorTimer(Sender: TObject);
{$IFDEF MSWINDOWS}
var
  P: TPoint;
  R: TRect;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  SetCursorHidden(FStereoOn and FDisplay.Settings.HideCursor and GetCursorPos(P) and
    FDisplay.DisplayRect(R) and R.Contains(P));
  {$ENDIF}
end;

procedure TForm2.LeaveStereo;
begin
  if not FStereoOn then
    Exit;
  FStereoOn := False;
  FStereoWatch.Enabled := False;
  FCursorTimer.Enabled := False;
  SetCursorHidden(False);
  FEyes.Stop;
  FOutput.Hide;
  SizeViewForStereo(False);
  if FMainHidden then
  begin
    FMainHidden := False;
    Show;
  end;
  btnStereo.IsPressed := False;
  ShowStatus('Stereo off: the 3D window is hidden and the lens off; the display stays running');
end;

procedure TForm2.PlaceOutput(const ARect: TRect);
{$IFDEF MSWINDOWS}
var
  Wnd: NativeUInt;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  Wnd := FormToHWND(FOutput);
  SetWindowPos(Wnd, HWND_TOPMOST, ARect.Left, ARect.Top, ARect.Width, ARect.Height,
    SWP_SHOWWINDOW);
  // Moving onto a monitor of another scale makes Windows suggest a new size,
  // which FMX takes: put it back once that has been handled (LenticularDemoFMX's
  // full screen does the same)
  TThread.ForceQueue(nil,
    procedure
    var
      Got: TRect;
    begin
      if not FStereoOn then
        Exit;
      SetWindowPos(Wnd, HWND_TOPMOST, ARect.Left, ARect.Top, ARect.Width, ARect.Height,
        SWP_SHOWWINDOW);
      if GetWindowRect(Wnd, Got) then
        ShowStatus(Format('3D window now at (%d, %d) %d x %d physical pixels',
          [Got.Left, Got.Top, Got.Width, Got.Height]));
    end);
  {$ELSE}
  FOutput.SetBounds(ARect.Left, ARect.Top, ARect.Width, ARect.Height);
  {$ENDIF}
end;

//** @abstract(Picks one of two strings.)
//**
//** @param(ACondition Which to pick.)
//**
//** @param(AWhenTrue The string for True.)
//**
//** @param(AWhenFalse The string for False.)
//**
//** @returns(The chosen string.)
function IfThenStr(ACondition: Boolean; const AWhenTrue, AWhenFalse: string): string;
begin
  if ACondition then
    Result := AWhenTrue
  else
    Result := AWhenFalse;
end;

procedure TForm2.SizeViewForStereo(AOn: Boolean);
var
  Info: TLNBDisplayInfo;
  Scale, W, H: Single;
begin
  FResizing := True;
  try
    if AOn then
    begin
      // Each eye is rendered at FEyes.RenderScale times the view the
      // display weaves, whatever this window's size: the glass takes up only
      // part of each eye's picture, which is cut out and scaled to the view
      W := PEARDOX_EYES_DEFAULT_VIEW_WIDTH;
      H := PEARDOX_EYES_DEFAULT_VIEW_HEIGHT;
      if FDisplay.DisplayInfo(Info) and (Info.recommendedViewWidth > 0) and
        (Info.recommendedViewHeight > 0) then
      begin
        W := Info.recommendedViewWidth;
        H := Info.recommendedViewHeight;
      end;
      W := W * FEyes.RenderScale;
      H := H * FEyes.RenderScale;
      // Where this window stays in sight, the viewport goes onto FRenderForm,
      // which is never seen. Owner (20:02, 20:15): on another monitor the
      // main window flashed horribly however the viewport was hidden in it -
      // Gorilla3D's render shows in the window it is on, and an opaque
      // cover over it did not help (and cost 14 ms a frame); an invisible
      // viewport is not rendered at all (20:10: black). With this window
      // hidden (it was on the 3D display) the viewport stays here: 70 fps,
      // render 5.7 ms (19:58)
      if not FMainHidden then
      begin
        // The display by name (owner, 20:29)
        FStereoNote.Text := 'Showing in glasses-free 3D on ' + FDisplay.DisplayName +
          sLineBreak + 'Esc or Stereo turns it off';
        GorillaViewport1.Parent := FRenderForm;
        FStereoCover.Visible := True;
        FStereoCover.BringToFront;
      end;
      // Gorilla3D draws at the viewport's size in logical units, which zero
      // copy hands on as it is (StereoCam47's probe: a 1280 x 720 viewport
      // drew 1280 x 720 at scale 1.5); MakeScreenshot gives physical pixels
      Scale := 1;
      if (GorillaViewport1.Scene <> nil) and not FEyes.ZeroCopyPossible then
        Scale := GorillaViewport1.Scene.GetSceneScale;
      ViewLayout.ClipChildren := True;
      GorillaViewport1.Align := TAlignLayout.None;
      if GorillaViewport1.Parent = FRenderForm then
      begin
        FRenderForm.ClientWidth := Ceil(W / Scale);
        FRenderForm.ClientHeight := Ceil(H / Scale);
        GorillaViewport1.SetBounds(0, 0, W / Scale, H / Scale);
      end
      else
        GorillaViewport1.SetBounds((ViewLayout.Width - W / Scale) / 2,
          (ViewLayout.Height - H / Scale) / 2, W / Scale, H / Scale);
      ShowStatus(Format('Stereo: each eye rendered at %.0f x %.0f physical pixels, on %s',
        [W, H, IfThenStr(GorillaViewport1.Parent = FRenderForm,
        'the hidden render window', 'this (hidden) window')]));
    end
    else
    begin
      FStereoCover.Visible := False;
      if GorillaViewport1.Parent <> ViewLayout then
      begin
        GorillaViewport1.Parent := ViewLayout;
        FStereoCover.BringToFront;
      end;
      GorillaViewport1.Align := TAlignLayout.Client;
    end;
  finally
    FResizing := False;
  end;
end;

procedure TForm2.OutputClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := TCloseAction.caHide;
  TThread.ForceQueue(nil, LeaveStereo);
end;

procedure TForm2.DisplayLog(Sender: TObject; const AText: string);
begin
  ShowStatus(AText);
end;

procedure TForm2.DisplayStarted(Sender: TObject);
{$IFDEF MSWINDOWS}
var
  Child: NativeUInt;
  N: Integer;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  FDisplayParent := FormToHWND(FOutput);
  // The bridge's window is the 3D window's only native child: the mouse is
  // passed through it to the 3D window (FOutputHost's handlers)
  N := 0;
  Child := GetWindow(FDisplayParent, GW_CHILD);
  while Child <> 0 do
  begin
    if SetWindowSubclass(Child, @PassMouseThrough, PASS_MOUSE_SUBCLASS_ID, 0) then
      Inc(N);
    Child := GetWindow(Child, GW_HWNDNEXT);
  end;
  ShowStatus(Format('Mouse passed through %d window(s) of the bridge to the 3D window', [N]));
  {$ENDIF}
  btnStereo.Enabled := True;
  // Started again on a new 3D window (see EnterStereo): weave now
  if FStereoOn then
  begin
    ShowStatus('The display started again on the 3D window: weaving');
    StartWeaving;
  end
  else
    ShowStatus('Display ready: Stereo turns glasses-free 3D on, full screen on the 3D display');
end;

procedure TForm2.DisplayStopped(Sender: TObject);
begin
  if FRestarting then
    Exit;
  LeaveStereo;
  FEyes.ReleaseZeroCopy;
  btnStereo.Enabled := False;
end;

procedure TForm2.EyesLog(Sender: TObject; const AText: string);
begin
  ShowStatus(AText);
end;

{$IFNDEF MSWINDOWS}
// Windows has the keyboard hook instead (H2219 there, owner 21:37)
procedure TForm2.FormKeyUp(Sender: TObject; var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
begin
  // Key-up gives the key's code, not a character
  if IsTestKey(Key) then
    HandleKey(Key);
end;
{$ENDIF}

class function TForm2.IsTestKey(AKey: Word): Boolean;
begin
  case AKey of
    vkL, vkLeftBracket, vkRightBracket, vkP, vkHome, vkC, vkV, vkComma, vkPeriod, vkM, vkW:
      Result := True;
  else
    Result := False;
  end;
end;

function TForm2.HookKey(AKey: Word; AIsRepeat: Boolean): Boolean;
begin
  Result := False;
  {$IFDEF MSWINDOWS}
  // Not while a dialog (the open dialog's file name box) has the keyboard
  if (GetActiveWindow <> FormToHWND(Self)) and
    ((FOutput = nil) or (GetActiveWindow <> FormToHWND(FOutput))) then
    Exit;
  {$ENDIF}
  // Esc turns Stereo off (owner, 19:43); otherwise it goes on as usual
  if (AKey = vkEscape) and FStereoOn then
  begin
    Result := True;
    if not AIsRepeat then
      TThread.ForceQueue(nil,
        procedure
        begin
          if KeyHookForm <> nil then
            KeyHookForm.LeaveStereo;
        end);
    Exit;
  end;
  if not IsTestKey(AKey) then
    Exit;
  Result := True;
  if AIsRepeat then
    Exit;
  // Outside the hook: the key's action may log, resize, restart the display
  TThread.ForceQueue(nil,
    procedure
    begin
      if KeyHookForm <> nil then
        KeyHookForm.HandleKey(AKey);
    end);
end;

procedure TForm2.HandleKey(AKey: Word);
var
  Sep, Scale: Double;
begin
  case AKey of
    vkL:
      begin
        // 0 (the runtime's own) .. LATENCY_MAX_FRAMES, round and round
        FDisplay.SetLatencyFrames((FDisplay.Settings.LatencyFrames + 1) mod (LATENCY_MAX_FRAMES + 1));
        FDisplay.SaveSettings;
      end;
    vkLeftBracket, vkRightBracket:
      begin
        Sep := FDisplay.Settings.EyeSeparationMM;
        // 0 means "as tracked": the keys start from the usual 63 mm
        if Sep <= 0 then
          Sep := LENTICULAR_DEFAULT_EYE_SEPARATION_MM;
        if AKey = vkLeftBracket then
          Sep := Sep - EYE_SEPARATION_STEP_MM
        else
          Sep := Sep + EYE_SEPARATION_STEP_MM;
        FDisplay.Settings.EyeSeparationMM := EnsureRange(Sep, EYE_SEPARATION_MIN_MM,
          EYE_SEPARATION_MAX_MM);
        ShowStatus(Format('Eye separation %.0f mm', [FDisplay.Settings.EyeSeparationMM]));
        FDisplay.SaveSettings;
      end;
    vkP:
      FEyes.LogSnapshot('StereoModel view: ' + ViewText + ' | model ' +
        ExtractFileName(FModelPath));
    vkHome:
      if (FModel <> nil) and SameText(ExtractFileName(FModelPath), TEST_MODEL) then
        TestView
      else
        ResetView;
    vkC:
      begin
        // Owner's Release log (19:27): off, submit 8 -> 0.9 ms and 24 -> 32
        // fps; "No difference visually" (19:30), so off is the default
        FDisplay.SetFrameCap(not FDisplay.Settings.FrameCap);
        FDisplay.SaveSettings;
      end;
    vkV, vkComma, vkPeriod:
      begin
        // The per-eye view on and off (off: full speed), and its render
        // scale (owner, 22:37); the viewport is made the new size at once
        if AKey = vkV then
          FDisplay.Settings.PerEyeView := not FDisplay.Settings.PerEyeView
        else
        begin
          Scale := EnsureRange(FDisplay.Settings.RenderScale, LENTICULAR_MIN_RENDER_SCALE,
            LENTICULAR_MAX_RENDER_SCALE);
          if AKey = vkComma then
            Scale := Scale - RENDER_SCALE_STEP
          else
            Scale := Scale + RENDER_SCALE_STEP;
          FDisplay.Settings.RenderScale := EnsureRange(Scale, LENTICULAR_MIN_RENDER_SCALE,
            LENTICULAR_MAX_RENDER_SCALE);
        end;
        FDisplay.SaveSettings;
        if FStereoOn then
          SizeViewForStereo(True);
        ShowStatus(Format('Per-eye view %s, render scale %.2f (used: %.2f)',
          [IfThenStr(FDisplay.Settings.PerEyeView, 'on', 'off (full speed)'),
          FDisplay.Settings.RenderScale, FEyes.RenderScale]));
      end;
    vkM:
      begin
        FDisplay.Settings.HideCursor := not FDisplay.Settings.HideCursor;
        FDisplay.SaveSettings;
        CursorTimer(nil);
        ShowStatus('Mouse pointer hidden over the 3D display: ' +
          BoolToStr(FDisplay.Settings.HideCursor, True));
      end;
    vkW:
      begin
        // Off: one flat view, lens off, for screen recordings (owner, 22:37)
        FDisplay.Settings.Weave := not FDisplay.Settings.Weave;
        FDisplay.SaveSettings;
        ShowStatus(IfThenStr(FDisplay.Settings.Weave, 'Weave on: glasses-free 3D',
          'Weave off: one flat view from between the eyes, the lens off (for recording)'));
      end;
  end;
end;

procedure TForm2.DisplayProblem(Sender: TObject; AProblem: TLenticularDisplayProblem;
  const AMessage: string);
begin
  // Also when a restart on a new 3D window fails
  LeaveStereo;
  btnStereo.IsPressed := False;
  btnStereo.Enabled := False;
  ShowStatus('Glasses-free 3D not started: ' + AMessage);
end;

procedure TForm2.FormShow(Sender: TObject);
begin
  if FLoadQueued then
    Exit;
  FLoadQueued := True;
  // After this event has finished, so the window is drawn before the load
  // and before glasses-free 3D starts
  TThread.ForceQueue(nil, FirstShown);
end;

procedure TForm2.ShowStatus(const AText: string);
begin
  FStatus.Text := AText;
  Log.d(AText);
  LogLine(AText);
end;

function TForm2.FindTestModel(out ATried: string): string;
var
  Folders: TStringList;
  Dir, UpDir: string;
  I: Integer;
begin
  Result := '';
  Folders := TStringList.Create;
  try
    Dir := ExtractFileDir(ExpandFileName(ParamStr(0)));
    // A deployed build: models beside the executable (Windows, Linux) or
    // in the bundle's Resources (macOS: the executable is in Contents/MacOS)
    Folders.Add(System.IOUtils.TPath.Combine(Dir, MODEL_FOLDER));
    Folders.Add(System.IOUtils.TPath.Combine(System.IOUtils.TPath.Combine(ExtractFileDir(Dir), 'Resources'), MODEL_FOLDER));
    // Android and iOS: System.StartUpCopy copies deployed files here
    Folders.Add(System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetDocumentsPath, MODEL_FOLDER));
    // Run from the IDE's output folder: the repository's models folder is
    // some way above it (StereoModel/<platform>/<config> on Windows)
    for I := 1 to FOLDERS_UP do
    begin
      UpDir := ExtractFileDir(Dir);
      if (UpDir = '') or (UpDir = Dir) then
        Break;
      Dir := UpDir;
      Folders.Add(System.IOUtils.TPath.Combine(Dir, MODEL_FOLDER));
    end;
    for I := 0 to Folders.Count - 1 do
      if TFile.Exists(System.IOUtils.TPath.Combine(Folders[I], TEST_MODEL)) then
        Exit(System.IOUtils.TPath.Combine(Folders[I], TEST_MODEL));
    ATried := string.Join('; ', Folders.ToStringArray);
  finally
    Folders.Free;
  end;
end;

procedure TForm2.TestView;
var
  Cam: TSpritelyOrbitalCamera;
  Fitted: Single;
begin
  Cam := SpritelyOrbitalCamera1;
  FZoom := 1;
  Cam.Azimuth := TEST_VIEW_AZIMUTH;
  Cam.PolarAngle := TEST_VIEW_INCLINATION;
  Cam.Roll := TEST_VIEW_ROLL;
  FitView;
  // The camera nearer or farther along its line of sight, the target
  // staying on the scene's axis; the wheel carries on from there
  Fitted := Cam.Distance;
  Cam.Distance := TEST_VIEW_DEPTH;
  if Fitted > 0 then
    FZoom := EnsureRange(Cam.Distance / Fitted, ZOOM_MIN, ZOOM_MAX);
  ShowView;
  ShowStatus('Test view: ' + ViewText);
end;

procedure TForm2.LoadTestModel;
var
  Path, Tried: string;
begin
  Path := FindTestModel(Tried);
  if Path = '' then
    ShowStatus(Format('Model NOT FOUND: %s is in none of: %s', [TEST_MODEL, Tried]))
  else if LoadModel(Path) and SameText(ExtractFileName(Path), TEST_MODEL) then
    TestView;
end;

function TForm2.LoadModel(const APath: string): Boolean;
var
  NewModel: TGorillaModel;
begin
  Result := False;
  // Owned by the viewport as before, but made here and loaded with
  // LoadFromFile, as Sprite3D does: TGorillaModel.LoadNewModelFromFile
  // (Gorilla3D 1.5.3) never frees the FBX loader's parse tree, so every FBX
  // file it loads leaks it (TFBXNode, TFBXProperty and their lists)
  NewModel := TGorillaModel.Create(GorillaViewport1);
  try
    NewModel.Parent := GorillaViewport1;
    // Gorilla3D chooses the loader by the extension
    NewModel.LoadFromFile(nil, APath, []);
  except
    on E: Exception do
    begin
      // Made before the load now, so it goes if the load fails
      NewModel.Parent := nil;
      NewModel.Free;
      ShowStatus(Format('Model load FAILED: %s: %s: %s', [APath, E.ClassName, E.Message]));
      Exit;
    end;
  end;
  // Only now the old one goes; the camera lets go of it as its Subject
  // when it is freed
  FModel.Free;
  FModel := NewModel;
  FModelPath := APath;
  PlaceModel;
  // A model with animations plays its first (DemoScene's spinning
  // cubes); FAnimationBox chooses another
  FillAnimations;
  // The camera may not go inside the model: the wheel and orbits stop at
  // the face nearest the camera
  SpritelyOrbitalCamera1.Subject := FModel;
  ResetView;
  ShowStatus(Format('Loaded %s; azimuth %.1f, polar %.1f, distance %.2f, headlight %s',
    [APath, SpritelyOrbitalCamera1.Azimuth, SpritelyOrbitalCamera1.PolarAngle,
     SpritelyOrbitalCamera1.Distance, BoolToStr(SpritelyOrbitalCamera1.Light <> nil, True)]));
  Result := True;
end;

function TForm2.ModelFilter: string;
var
  Exts: TStringList;
  Key, Ext, All: string;
  I: Integer;
begin
  Exts := TStringList.Create;
  try
    Exts.Sorted := True;
    Exts.Duplicates := TDuplicates.dupIgnore;
    // The keys are the extensions; take them with or without the dot, in
    // any case
    for Key in TGorillaLoader.FileTypes.Keys do
    begin
      Ext := LowerCase(Key.Trim);
      if Ext.StartsWith('.') then
        Ext := Ext.Substring(1);
      if Ext <> '' then
        Exts.Add(Ext);
    end;
    All := '';
    for I := 0 to Exts.Count - 1 do
    begin
      if All <> '' then
        All := All + ';';
      All := All + '*.' + Exts[I];
    end;
    Result := '';
    if All <> '' then
      Result := Format(MODEL_FILTER_ALL, [All, All]);
    for I := 0 to Exts.Count - 1 do
      Result := Result + Format(MODEL_FILTER_ONE, [UpperCase(Exts[I]), Exts[I], Exts[I]]);
    Result := Result + MODEL_FILTER_ANY;
  finally
    Exts.Free;
  end;
end;

procedure TForm2.OpenMenuItemClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Filter := ModelFilter;
    Dialog.FilterIndex := 1;
    if FModelPath <> '' then
      Dialog.InitialDir := ExtractFileDir(FModelPath);
    Dialog.Options := Dialog.Options + [TOpenOption.ofFileMustExist];
    if Dialog.Execute then
      LoadModel(Dialog.FileName);
  finally
    Dialog.Free;
  end;
end;

procedure TForm2.PlaceModel;
var
  Box: TBoundingBox;
begin
  // As Sprite3D's PlaceModel: the model's own bounds, taken before it is
  // moved or turned, give its position; then the turn that stands it up
  Box := FModel.GetBoundingBox;
  FModel.Position.Point := Point3D(Box.TopLeftNear.X + (Box.Width / 2),
                                   Box.TopLeftNear.Y + (Box.Height / 2),
                                   Box.TopLeftNear.Z + (Box.Depth / 2));
  FModel.RotationAngle.X := MODEL_TURN_X;
  FModel.RotationAngle.Y := 0;
  FModel.RotationAngle.Z := 0;
end;

procedure TForm2.FitView;
begin
  if FModel = nil then
    Exit;
  // For every angle, so orbiting never needs a refit; only the view's
  // shape does. The wheel's zoom is then put back on top of the fit
  if not SpritelyOrbitalCamera1.FitToBoundsMax(FModel, VIEW_MARGIN) then
    ShowStatus('Framing FAILED: no camera, an empty model or a viewport with no size')
  else if not SameValue(FZoom, 1) then
    SpritelyOrbitalCamera1.Zoom(FZoom);
  ShowView;
end;

procedure TForm2.ResetView;
begin
  FZoom := 1;
  SpritelyOrbitalCamera1.Azimuth := 0;
  SpritelyOrbitalCamera1.PolarAngle := 0;
  SpritelyOrbitalCamera1.Roll := 0;
  FitView;
end;

function TForm2.ModelDepth(out ADepth: Single): Boolean;
var
  Cam: TSpritelyOrbitalCamera;
  Eye, Forward, Centre: TPoint3D;
  Box: TBoundingBox;
begin
  ADepth := 0;
  Cam := SpritelyOrbitalCamera1;
  Result := (FModel <> nil) and (Cam.Camera <> nil) and (Cam.Distance > 0);
  if not Result then
    Exit;
  Eye := Cam.Camera.CameraPosition;
  Forward := (Cam.Camera.OrbitCenter.Point - Eye).Normalize;
  Box := FModel.GetAbsoluteBoundingBox;
  Centre := Point3D(Box.TopLeftNear.X + (Box.Width / 2), Box.TopLeftNear.Y + (Box.Height / 2),
    Box.TopLeftNear.Z + (Box.Depth / 2));
  // Along the line of sight, as the glass is square to it
  ADepth := (Centre - Eye).DotProduct(Forward);
end;

function TForm2.ViewText: string;
var
  Cam: TSpritelyOrbitalCamera;
  Depth: Single;
begin
  Cam := SpritelyOrbitalCamera1;
  Result := Format('azimuth %.1f, inclination %.1f, roll %.1f | target depth %.3f',
    [Cam.Azimuth, Cam.PolarAngle, Cam.Roll, Cam.Distance]);
  if ModelDepth(Depth) then
    Result := Result + Format(' | model centre Z %.3f', [Depth - Cam.Distance]);
end;

procedure TForm2.ShowView;
begin
  Caption := 'StereoModel | ' + ViewText;
end;

function TForm2.DepthStatus: string;
var
  Cam: TSpritelyOrbitalCamera;
  Depth, Z, MMPerUnit: Single;
  Where: string;
begin
  Cam := SpritelyOrbitalCamera1;
  Result := Format('Target depth %.3f', [Cam.Distance]);
  if not ModelDepth(Depth) then
    Exit;
  Z := Depth - Cam.Distance;
  if Z < 0 then
    Where := 'in front of the glass (out of the screen)'
  else
    Where := 'behind the glass';
  Result := Format('%s | model centre at depth %.3f: Z %.3f, %s',
    [Result, Depth, Z, Where]);
  // The view's height at the target's depth is the view's height on the
  // display; FOV is the vertical field of view
  if FDisplay.Running and (FDisplay.WindowSizeMM.Height > 0) then
  begin
    MMPerUnit := FDisplay.WindowSizeMM.Height /
      (2 * Cam.Distance * Tan(DegToRad(Cam.FOV) / 2));
    Result := Result + Format(', %.0f mm', [Z * MMPerUnit]);
  end;
  if SameValue(Cam.Distance, GorillaViewport1.FarPlane, GorillaViewport1.FarPlane * 0.001) then
    Result := Result + ' - AT THE LIMIT (the viewport''s far plane)';
end;

procedure TForm2.ViewResize(Sender: TObject);
begin
  // Not for Stereo's change of size, or its undoing: the view stays as the
  // user left it
  if FResizing then
    Exit;
  FitView;
end;

procedure TForm2.ViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  // Left drags orbit, right drags move the target's depth; a click on its
  // own does nothing (owner, 7 November 2026: no click resets the view)
  if Button in [TMouseButton.mbLeft, TMouseButton.mbRight] then
  begin
    FDragging := True;
    FDepthDrag := Button = TMouseButton.mbRight;
    FDragLast := PointF(X, Y);
  end;
end;

procedure TForm2.ViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if not FDragging then
    Exit;
  // A button let go outside the view sends no mouse-up, so the first move
  // without it ends the drag (as in Sprite3D)
  if (FDepthDrag and not (ssRight in Shift)) or (not FDepthDrag and not (ssLeft in Shift)) then
  begin
    FDragging := False;
    Exit;
  end;
  if FDepthDrag then
  begin
    // Up (Y falling) pushes the target deeper, down pulls it nearer; the
    // camera and the picture stay as they are (owner, 7 November 2026: the
    // depth will matter for the 3D display). Across is not used
    SpritelyOrbitalCamera1.SetTargetDepth(SpritelyOrbitalCamera1.Distance
      * Power(DEPTH_STEP_PER_PIXEL, FDragLast.Y - Y));
    ShowStatus(DepthStatus);
  end
  else
    // Dragging right turns the camera right round the centre (owner, 7
    // November 2026: the other way round felt reversed); dragging down
    // raises the camera
    SpritelyOrbitalCamera1.Orbit((X - FDragLast.X) * ORBIT_DEGREES_PER_PIXEL,
      (Y - FDragLast.Y) * ORBIT_DEGREES_PER_PIXEL);
  FDragLast := PointF(X, Y);
  ShowView;
end;

procedure TForm2.ViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  if FDragging and (((Button = TMouseButton.mbLeft) and not FDepthDrag) or
    ((Button = TMouseButton.mbRight) and FDepthDrag)) then
  begin
    FDragging := False;
    // Where the drag left the view, in the log, to note down
    ShowStatus('View: ' + ViewText);
  end;
end;

procedure TForm2.ViewMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
var
  Cam: TSpritelyOrbitalCamera;
  NewZoom, Before, ToModel, NewToModel, NewDistance: Single;
  Box: TBoundingBox;
  Centre: TPoint3D;
begin
  Handled := True;
  Cam := SpritelyOrbitalCamera1;
  // Rolling the wheel away (positive) brings the view nearer
  NewZoom := EnsureRange(FZoom * Power(ZOOM_STEP, -WheelDelta / WHEEL_NOTCH), ZOOM_MIN, ZOOM_MAX);
  if (FModel = nil) or (Cam.Camera = nil) or
    (Cam.ProjectionMode <> TGorillaCameraProjection.cpPerspective) then
  begin
    // Orthographic: Zoom scales the view's size, which is how big things
    // look, so only the change is passed on
    Cam.Zoom(NewZoom / FZoom);
    FZoom := NewZoom;
    ShowView;
    Exit;
  end;
  // Perspective: the step is a share of the camera's distance from the
  // MODEL, not from the target. Once a right drag has put the target far
  // deeper (or nearer) than the model, a share of the target's distance
  // made each notch a huge jump (owner, 16:40). The camera still moves
  // along its line of sight, towards or away from the target, by that step
  Box := FModel.GetAbsoluteBoundingBox;
  Centre := Point3D(Box.TopLeftNear.X + (Box.Width / 2), Box.TopLeftNear.Y + (Box.Height / 2),
    Box.TopLeftNear.Z + (Box.Depth / 2));
  ToModel := Cam.Camera.CameraPosition.Distance(Centre);
  Before := Cam.Distance;
  if (ToModel <= 0) or (Before <= 0) then
    Exit;
  NewToModel := ToModel * NewZoom / FZoom;
  NewDistance := Before - (ToModel - NewToModel);
  // With the target nearer than the model the camera cannot pass it: it
  // stops just short (a right drag down moves the target deeper again)
  if NewDistance < Before * MIN_TARGET_SHARE then
  begin
    NewDistance := Before * MIN_TARGET_SHARE;
    ShowStatus(Format('Zoom stopped: the target (depth %.3f) is in front of the model; ' +
      'right-drag up to move it deeper', [Before]));
  end;
  // The camera also stops at the model's nearest face (Subject)
  Cam.Zoom(NewDistance / Before);
  // What the distance to the model really became, so the first notch back
  // out moves the camera at once however far the wheel went in
  FZoom := EnsureRange(FZoom * Cam.Camera.CameraPosition.Distance(Centre) / ToModel,
    ZOOM_MIN, ZOOM_MAX);
  ShowView;
end;

initialization

finalization
  {$IFDEF MSWINDOWS}
  // Closed by FormClose normally; this only covers a fault
  RemoveKeyHook;
  {$ENDIF}

end.
