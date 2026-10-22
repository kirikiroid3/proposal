// Visual novel engine: an analyzable model for preview, jump and save
// Compile: typst compile vn-engine-proposal.typ
// Requires @preview/fletcher:0.5.8

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

// ---------------------------------------------------------------- style
#let accent = rgb("#2f5d8a")
#let soft = rgb("#eef3f8")
#let warn = rgb("#fbf1e4")
#let warn-line = rgb("#c98a2b")

#set document(
  title: "An Analyzable Model for a Visual Novel Engine",
  keywords: ("visual novel", "pushdown systems", "model checking", "game engine"),
)
#set page(
  paper: "a4",
  margin: (x: 22mm, top: 24mm, bottom: 24mm),
  numbering: "1",
  header: context {
    if counter(page).get().first() > 1 [
      #set text(8pt, fill: luma(110))
      An Analyzable Model for a Visual Novel Engine #h(1fr) Draft for discussion
    ]
  },
)
#set text(font: ("New Computer Modern", "Noto Serif CJK JP"), size: 10.5pt, lang: "en")
#set par(justify: true, leading: 0.68em)
#set heading(numbering: "1.1")
#show heading: set text(font: ("Noto Sans CJK JP"), weight: "bold", fill: accent)
#show heading.where(level: 1): it => { v(0.8em); it; v(0.3em) }
#show raw: set text(font: ("DejaVu Sans Mono", "Noto Sans CJK JP"), size: 8.6pt)
#show raw.where(block: true): block.with(
  fill: luma(246), inset: 9pt, radius: 3pt, width: 100%, stroke: 0.4pt + luma(220),
)
#show figure.caption: set text(size: 9pt)
#show figure: set block(breakable: false)
#set table(stroke: 0.4pt + luma(200), inset: 6pt)
#show table.cell.where(y: 0): set text(weight: "bold")
#show link: set text(fill: accent)

#let callout(title, body, fill: soft, line: accent) = block(
  fill: fill, stroke: (left: 2.5pt + line), inset: (x: 11pt, y: 9pt), width: 100%, radius: (right: 3pt),
)[#text(weight: "bold", fill: line, font: "Noto Sans CJK JP", size: 9.5pt)[#title] \ #body]
#let decision(body) = callout("Proposed decision", body)
#let question(body) = callout("Open question", body, fill: warn, line: warn-line)

// fletcher defaults
#let fd = (
  node-stroke: 0.6pt + luma(90),
  node-corner-radius: 3pt,
  node-inset: 6pt,
  edge-stroke: 0.6pt,
  label-size: 8pt,
)
#let small(x) = text(size: 8.5pt, x)

// ---------------------------------------------------------------- title
#align(center)[
  #v(4mm)
  #text(19pt, weight: "bold", font: "Noto Sans CJK JP", fill: accent)[
    An Analyzable Model for a Visual Novel Engine
  ]
  #v(1mm)
  #text(12pt, fill: luma(70))[Realtime preview, arbitrary jump and robust saves \ from a pushdown narrative core]
  #v(2mm)
  #text(9.5pt, fill: luma(100))[Design proposal · draft for team discussion · 22 October 2026]
]
#v(3mm)

#block(inset: (x: 8mm))[
  #set text(9.5pt)
  #set par(justify: true)
  *Summary.* Debugging a visual novel (VN) is hard because the correct behaviour lives in the
  author's head: which sprite should be on screen after a merge, which route a line belongs to,
  which flags must hold. Existing tools cannot jump to an arbitrary point with correct state.
  We propose to model a VN as a *deterministic transducer over choice histories*: a pushdown
  control structure over finite data computes the narrative state, and a pure function maps that
  state to presentation. This one decision makes saves, preview, jumping and static checking
  fall out of well-studied theory: pushdown reachability, symbolic model checking with decision
  diagrams, abstract interpretation and partial-order reduction. The document fixes the model,
  the restrictions on the script language that keep it analyzable, the save format, the preview
  mechanism, the linter, and a phased plan. Section 11 lists the questions we need to settle.

  This draft supersedes the draft of 16 October 2026, revised 19 October 2026 (proposal1). The
  model, the goals and the theory are unchanged. The XML script, the separate system scope and
  the `.kirp` render files are replaced by one Rust-like language with three function kinds
  (Section 3.4).
]

#outline(depth: 1, indent: auto)

// ================================================================
= Problem and goals

A VN is mostly linear text with occasional choices, but its state is invisible. A bug report such
as "the wrong character is on screen after the roof scene" is only reproducible if one knows
_which_ path led there, and only diagnosable if one knows what the author _meant_ to show.
Neither a teammate nor an AI agent has that knowledge today, so debugging falls back to the
author replaying the game.

#block(breakable: false, table(
  columns: (auto, 1fr),
  [Goal], [Requirement],
  [G1 Realtime preview], [Editing a line updates the preview at the current position without restarting the game.],
  [G2 Arbitrary jump], [Open any line in a _reachable, consistent_ state, not a guessed one.],
  [G3 Robust saves], [Saves survive script edits, and when they cannot, the engine says exactly where they diverge.],
  [G4 Checkable intent], [The author's assumptions become machine-checkable facts that a linter, a teammate or an agent can query.],
))

== Prior art

Two existing tools show both halves of what we want and where each stops.

- *Ren'Py "warp to line"* searches the scene graph for a path to the target line and
  replays only the `scene`, `show` and `hide` statements on it. Python code on the path is not run, so
  variables may be uninitialized, and authors patch state by hand in an `after_warp`
  label. The path search ignores game logic, so the chosen path may not be reachable, and only
  one path is examined @renpywarp.
- *Inky*, the editor for inkle's ink, keeps the player's choices and after each recompile
  fast-forwards to the last point the author reached @inky. That is trace replay: correct
  state, but only for the path the author happened to click through.

Our proposal combines the two: Inky-style replay for correctness, plus a logic-aware search
(Ren'Py's idea, done soundly) for reaching places the author has not clicked to.

// ================================================================
= The core abstraction

== A VN is a transducer over choice histories

Let $Sigma$ be the set of input events, mostly choices, each with a stable identifier. A play
session is a word $h in Sigma^*$. The engine is defined by three pure pieces:

$ sigma_h = "fold"(delta, sigma_0, h) quad quad R = f("pos", sigma_h, t) $

where $delta$ is the narrative transition function, $sigma$ is the narrative state (position,
call stack, variables), and $f$ maps the current position, state and local time $t$ to a screen
$R$. Everything else in the design follows from keeping $delta$ cheap and total and keeping $f$
free of hidden state.

#figure(
  diagram(
    ..fd,
    spacing: (9mm, 9mm),
    node((0, 0), align(center)[Choice trace \ #small[$h in Sigma^*$]], name: <h>),
    node((1, 0), align(center)[Narrative core \ #small[fold of $delta$]], name: <d>, fill: soft),
    node((2, 0), align(center)[Configuration \ #small[(pos, stack, $sigma$)]], name: <s>),
    node((3, 0), align(center)[Presentation \ #small[$f("pos", sigma, t)$]], name: <f>, fill: soft),
    node((4, 0), align(center)[Screen \ #small[$R$]], name: <r>, shape: rect),
    edge(<h>, <d>, "-|>"),
    edge(<d>, <s>, "-|>"),
    edge(<s>, <f>, "-|>"),
    edge(<f>, <r>, "-|>"),
    node((1, 1), align(center)[Save file \ #small[trace + snapshot]], name: <save>, stroke: (dash: "dashed")),
    edge(<h>, <save>, "--", bend: -20deg),
    edge(<s>, <save>, "--", bend: 20deg),
    node((3, 1), align(center)[Analyzer \ #small[reachability, lints]], name: <a>, stroke: (dash: "dashed")),
    edge(<a>, <d>, "--"),
  ),
  caption: [The engine as a pipeline. Only the narrative core is replayed when fast-forwarding;
    presentation is evaluated lazily at the destination. The analyzer works on the same narrative
    IR as the narrative core.],
) <fig-pipeline>

== What should the state be?

There is a principled answer. Two histories $h_1, h_2$ are *equivalent* when no future input can
tell them apart by what appears on screen:

$ h_1 tilde h_2 quad <==> quad forall z in Sigma^*. space "screens"(h_1 z) = "screens"(h_2 z) . $

This is the Myhill–Nerode congruence @nerode1958 @hopcroft2006 lifted from acceptors to
output-producing machines. The raw history is the largest possible state, the equivalence class
$[h]$ is the smallest, and the author's flags sit in between. Most of this proposal is about
moving the engine's state toward $[h]$, or avoiding the need to compute it at all.

#figure(
  diagram(
    ..fd,
    spacing: (34mm, 6mm),
    node((0, 0), align(center)[Raw history $h$ \ #small[maximal; always correct]]),
    node((1, 0), align(center)[Author flags $sigma$ \ #small[what the script declares]], fill: soft),
    node((2, 0), align(center)[Nerode class $[h]$ \ #small[minimal; exact]]),
    edge((0, 0), (1, 0), "-|>", [forget order]),
    edge((1, 0), (2, 0), "-|>", [merge equal futures]),
  ),
  caption: [Three granularities of state. Liveness analysis and bisimulation minimization
    (Section 5.4) move from the middle toward the right.],
)

// ================================================================
= Control model: pushdown control over finite data

== The halting problem comes from data, not from the stack

A pushdown automaton by itself has decidable reachability. Undecidability comes from unbounded
_data_: two unbounded counters with conditional jumps already form a Minsky machine, which is
Turing-complete without any stack @minsky1967. So the rule is:

- *Control* may be recursive. Scenes call other scenes and return. Loops are allowed (hub maps,
  day cycles).
- *Data* ranges over finite domains: booleans, enums, bounded or saturating integers.

The result is a pushdown system with finite control, for which reachability ($"pre"^*$ and
$"post"^*$) is computable in polynomial time in the size of the system @bouajjani1997
@schwoon2002. One caveat for planning: the size of the system is exponential in the number of
boolean variables, which is why we need symbolic representations (Section 5).

What we actually require is weaker than "the game halts", and both properties hold under these
rules:

+ *Each step terminates.* Code between two input points is total. This needs every loop _and_
  every cycle of calls to pass through an input point: a scene that calls itself before any input
  grows the stack forever inside one step.
+ *Reachability queries are decidable*, e.g. "can line 412 be reached with `MET_B` false?"

== What a pushdown language looks like

The program-shaped form of a pushdown system is a *Boolean program* (Ball and Rajamani's SLAM
project @ball2000boolean @ball2000bebop); its graphical twin is a *recursive state machine*
(RSM) @alur2005. In Kagari the restriction applies to exactly one function kind, `pushdown fn`,
in which all narrative code is written (Section 3.4). A `pushdown fn` marked `#[scene]` is a
scene: an RSM component that may suspend at steps. A `pushdown fn` without it is an instant
procedure that runs without input. The other kinds, `fn` and `const fn`, have the full language.
Inside a `pushdown fn`:

#figure(caption: [What a `pushdown fn` allows and forbids. Each rule is checked by the type and
  kind checker, so a violation is a type error.], table(
  columns: (1fr, 1fr),
  align: left,
  [Allowed in `pushdown fn`], [Forbidden (and why)],
  [Locals, parameters, return values and story statics (`static mut`) of finite type: `bool`,
    `()`, `Int<lo, hi>`, enums with finite payloads, structs, tuples and arrays `[T; N]` of finite
    types, `Option<T>`, `Text` constants, asset handles],
  [Rust integers (`u8` … `i128`, `usize`), `Rat`, `Decimal`, `String`, `Vec`, maps, `Screen`:
    they reintroduce counters, hence Turing completeness],
  [In a scene: calls to scenes, including recursion, to instant procedures and to `push_step`.
    In an instant procedure: calls to instant procedures, with an acyclic call graph. In both:
    calls to `const fn` that are folded or tabulated (Section 3.4)],
  [Calls to `fn`: Turing-complete code would make $sigma$ unbounded],
  [Function pointers of kind `scene fn`, `pushdown fn` or `const fn`, stored in $sigma$ and
    called. The set of named functions is finite, so a call through a pointer is a case split:
    the computed call over a finite enum of proposal1],
  [First-class closures (stored, returned, captured): closures are second-class, passed as an
    argument and called only, and instant: a closure cannot step or call a scene. Higher-order
    recursion schemes are decidable but #box[$n$-EXPTIME]-complete for order $n$ @ong2006],
  [In a scene: `loop` and `while` whose body passes a step on every path, and recursion cycles
    that pass a step. Everywhere: `for` over a constant range or array],
  [Loops, or cycles of calls, with no step and no bound: a single step might not terminate],
  [`push_step` (input), written with the forms `s!(…)` and `choice!{…}`; output through the
    `render` attribute of a step],
  [Reading the screen, wall-clock time, OS state or meta (see the meta layer, Section 8.3): only
    `fn` code can, and a `pushdown fn` cannot call it],
))

One rule of proposal1 is gone from the table. Jumping into the middle of another scene broke
well-nested call and return and had to be checked. It is now impossible by construction: the
language has `if`, `match`, `loop`, `while`, `for`, `break`, `continue` and `return`, but no
`goto` and no labels as positions, so control leaves a function only by a call or a return.
Irreducible control flow is not expressible, by design.

A stack frame is a return address plus the caller's locals. Both are finite, so the stack
alphabet is finite: that is exactly the definition of a pushdown system.

== When the stack matters: the 学園祭 example

The basic festival hub does *not* need a stack. The player goes from the campus map to stall A, B
or C, the story plays, and control always returns to the same place, the map. A revisited stall
prints a short message and returns. Each stall is called from one place only, so the calls can be
inlined. The only memory is the position and three `VISITED` bits, so this is a finite automaton.

#figure(
  diagram(
    ..fd,
    spacing: (16mm, 11mm),
    node((1, 0), [Campus map], name: <map>, fill: soft),
    node((0, 1), [Stall A], name: <a>),
    node((1, 1), [Stall B], name: <b>),
    node((2, 1), [Stall C], name: <c>),
    node((1, -1), [Festival end], name: <end>),
    edge(<map>, <a>, "-|>", bend: -18deg),
    edge(<a>, <map>, "-|>", bend: -18deg),
    edge(<map>, <b>, "-|>", bend: -18deg),
    edge(<b>, <map>, "-|>", bend: -18deg),
    edge(<map>, <c>, "-|>", bend: 18deg),
    edge(<c>, <map>, "-|>", bend: 18deg),
    edge(<map>, <end>, "-|>", [`VISITED_A ∧ VISITED_B ∧ VISITED_C`], label-side: right),
  ),
  caption: [The single-day hub. Every stall returns to the same node, so a loop around one
    choice suffices. The state space is 5 control nodes $times$ $2^3$ flag values.],
)

The stack becomes useful when one sub-scene is entered from different places and must return to
different places:

- *Reused hub.* The festival runs on day 1 (afterwards: dorm) and day 2 (afterwards: ending check).
- *Interrupts.* A phone call can happen inside any stall or on the map, and afterwards the game resumes exactly where it was.

#figure(
  diagram(
    ..fd,
    spacing: (16mm, 8mm),
    node((0, 0), [`Day1`], name: <d1>),
    node((1, 0), [box: `FestivalHub`], name: <b1>, fill: soft),
    node((3, 0), [`DormNight`], name: <dn>),
    node((0, 3), [`Day2`], name: <d2>),
    node((1, 3), [box: `FestivalHub`], name: <b2>, fill: soft),
    node((3, 3), [`EndingCheck`], name: <ec>),
    edge(<d1>, <b1>, "-|>"),
    edge(<d2>, <b2>, "-|>"),
    node((-0.2, 1.5), text(8pt, fill: accent)[component \ `FestivalHub`], name: <lbl>, stroke: none),
    node((1, 1.5), [entry], name: <en>, shape: fletcher.shapes.pill),
    node((2, 1.5), [map ⇄ stalls], name: <hub>),
    node((3, 1.5), [exit], name: <ex>, shape: fletcher.shapes.pill),
    edge(<en>, <hub>, "-|>"),
    edge(<hub>, <ex>, "-|>"),
    node(enclose: (<lbl>, <en>, <hub>, <ex>), inset: 6pt, stroke: (paint: accent, dash: "dashed"), corner-radius: 6pt),
    edge(<b1>, <en>, "--|>", [call: push `Day1`], label-side: left),
    edge(<b2>, <en>, "--|>", [call: push `Day2`], label-side: right),
    edge(<ex>, <dn>, "--|>", [return: pop], label-side: right),
    edge(<ex>, <ec>, "--|>", [return: pop], label-side: left),
  ),
  caption: [A recursive state machine. Boxes are calls into another component; the stack
    remembers which box to return to. Without the stack, `FestivalHub` would have to be
    duplicated once per caller.],
) <fig-rsm>

#decision[
  Adopt the pushdown model. Its practical value is *succinctness*: with bounded call depth it
  recognizes exactly what a finite automaton does, but a finite automaton would need one copy of
  each shared scene per call site, and with nesting the copies multiply. With unbounded recursion
  it gains genuine context-free power at no cost to decidability.
]

In Kagari the day-1 part of the example reads as follows. Section 3.4 explains the syntax; this
is a `.kix` file, because it uses forms.

```rust
static mut VISITED_A: bool = false;
static mut VISITED_B: bool = false;
static mut VISITED_C: bool = false;

enum Map { A, B, C, Leave }

#[scene]
#[entry]
pushdown fn Day1() -> Ending {
    s!(t!["The school festival starts today."]);
    FestivalHub();
    DormNight();
    Ending::Normal
}

#[scene]
pushdown fn FestivalHub() {
    loop {
        match choice!{
            id = "map",
            t!["Go to stall A"] => Map::A,
            t!["Go to stall B"] => Map::B,
            t!["Go to stall C"] => Map::C,
            t!["Leave"] if VISITED_A && VISITED_B && VISITED_C => Map::Leave,
        } {
            Map::A => StallA(),
            Map::B => StallB(),
            Map::C => StallC(),
            Map::Leave => break,
        }
    }
}

#[scene]
pushdown fn StallA() {
    if VISITED_A {
        s!(t!["The stall is already packing up."]);
        return;
    }
    VISITED_A = true;
    s!(who = "Hanako", render = hanako_jumps, t!["Welcome to stall A!"]);
}

const fn hanako_jumps(mut screen: Screen) -> Screen {
    screen.entity(HANAKO).cord.apply_animation(jump(20));
    screen
}
```

The `loop` passes the choice on every path, so each step terminates. The `Leave` arm is offered
only when its `if` guard holds; the stuck-choice check proves that some arm is always offered.

== One language, three function kinds

Proposal1 had an XML story (`.kis`), a separate XML system scope, Rust-like render files
(`.kirp`) and Rust-like extension files (`.kix`): two scopes, three file kinds, two syntaxes. We
replace all of them by one Rust-like language with three function kinds.

#figure(caption: [The three function kinds.], table(
  columns: (auto, 1fr, 1fr),
  align: left,
  [Kind], [Meaning], [Runs],
  [`fn`], [Turing-complete], [at runtime: the system (UI, menus, saves, settings)],
  [`pushdown fn`], [pushdown control over finite data; a `#[scene]` may suspend at steps], [at runtime, inside the narrative],
  [`const fn`], [pure, deterministic, Turing-complete; total where it is evaluated],
  [at compile time (renders, constants, tabulation); may also be called at runtime],
))

#figure(caption: [Call rules. Rows are callers, columns are callees. A forbidden call is a type
  error.], table(
  columns: (auto, auto, 1fr, auto),
  align: left,
  [Caller / callee], [`fn`], [`pushdown fn`], [`const fn`],
  [`fn`], [yes], [no; only _starts_ a story through an `#[entry]` scene], [yes],
  [`pushdown fn`], [no], [yes: a scene calls scenes and instant procedures; an instant procedure calls instant procedures only], [yes, folded or tabulated],
  [`const fn`], [no], [no], [yes],
))

Function pointer types carry the kind: `fn(A) -> B`, `const fn(A) -> B`, `pushdown fn(A) -> B`
for an instant procedure and `scene fn(A) -> B` for a scene (tentative syntax; `scene` is a
keyword only in types). So a `pushdown fn` cannot reach an `fn` through a pointer either, and
an instant procedure cannot reach a scene. Const-ness is never inferred: `const fn` is written
explicitly, and a lint may suggest it.

=== Why the restriction lives on functions

The pushdown restriction is one property in one place. It is not an attribute, a file mode or a
separate scope. A `pushdown fn` may call only `pushdown fn` and `const fn`, so the narrative
fragment is closed under calls, and the analyzer needs only the functions reachable from the
`#[entry]` scenes. Everything else may be Turing-complete without touching the analysis: menus,
save screens and settings are ordinary `fn` code with first-class closures, signals and
collections. Proposal1 needed a second scope with its own syntax for the same separation.

The same reasoning fixes the closure rule. Closures capture by value. In `fn` and `const fn` they
are first-class, which UI handlers need. In `pushdown fn` they are second-class: they may be
passed as an argument and called, but never stored, returned or captured. They are also
instant: a closure cannot step or call a scene, so every step is a point in a named scene. A
stored closure would put a captured environment into $sigma$ and make the program a
higher-order recursion scheme. Model checking those is decidable, but
#box[$n$-EXPTIME]-complete for order $n$ @ong2006. Named function pointers do not have this
problem: their domain is the finite set of named functions.

=== The single channel from Turing-complete code

The only way from `fn` code into the narrative is to start an `#[entry]` scene. Entry scenes are
scenes with finite parameter and return types, written with both `#[entry]` and `#[scene]`; they
are the analysis roots and the only functions the system can start. The only ways back are the
entry scene's return value, which the
system's exit handler receives and must handle exhaustively, and write-only meta (Section 8.3).
Hence the whole narrative, from its start to any step, is pushdown, and G2 and G3 hold for every
run the system can start. The analyzer quantifies over all values of the entry arguments.

```rust
// story.kix
static CLEARED_MIO: Meta<bool> = meta(false);

enum Ending { Normal, Mio }
enum Confess { Yes, No }
enum Answer { Accepted, Rejected }

#[scene]
#[entry]
pushdown fn Prologue(cleared_mio: bool) -> Ending {
    if cleared_mio {
        s!(t!["The rooftop door is unlocked this time."]);
    }
    let answer = Confession();
    match answer {
        Answer::Accepted => {
            CLEARED_MIO.write(true);
            Ending::Mio
        }
        Answer::Rejected => Ending::Normal,
    }
}

#[scene]
pushdown fn Confession() -> Answer {
    s!(who = "Mio", t!["Is there something you want to tell me?"]);
    match choice!{
        id = "confess",
        t!["Tell her"] => Confess::Yes,
        t!["Say nothing"] => Confess::No,
    } {
        Confess::Yes => Answer::Accepted,
        Confess::No => Answer::Rejected,
    }
}

// system.kis: Turing-complete; std::system names are tentative
fn new_game() {
    nav::start(Prologue, (CLEARED_MIO.get(),), |ending| match ending {
        Ending::Normal => nav::goto(Title),
        Ending::Mio => nav::goto(Credits),
    });
}
```

=== Const functions and tabulation

A `pushdown fn` may call a `const fn` if every argument is a constant expression or of finite
type. With constant arguments the call is folded at compile time. With finite runtime arguments
the compiler *tabulates* the function over its whole argument domain. This proves that it
terminates on every input it can receive at runtime and turns it into a finite relation, which the
analyzer treats like any other finite transition. The result must be of finite type unless the
whole call is constant. A domain that is too large, or an evaluation that does not terminate
within the evaluation fuel, is a compile error.

```rust
enum Route { None, Mio, Haruka, Rin }

// Called from pushdown code with runtime arguments: tabulated over 4 × 6 values.
const fn bonus(route: Route, affection: Int<0, 5>) -> Int<0, 2> {
    match (route, affection) {
        (Route::Mio, 4..=5) => 2,
        (Route::Mio, _) | (_, 5) => 1,
        _ => 0,
    }
}
```

=== Files

#table(
  columns: (auto, 1fr),
  [Extension], [Syntax],
  [`.kis`], [The Rust-like language],
  [`.kix`], [`.kis` plus forms: `s!(…)`, `choice!{…}`, `t![…]` and the UI forms],
)

The extension selects the syntax only, never the semantics. Any function kind may appear in either
file. Forms are allowed only in `.kix`; a `.kis` file writes the struct expressions that forms
desugar to. Narrative is normally written in `.kix` for that reason. Modules are Rust-like (`mod`,
`pub`, `use`, paths with `::`), and one root file, `main.kix` by convention, is the compiler's
input.

=== Narrative forms are sugar

A *form* is written `name!(…)`, `name![…]` or `name!{…}`. Forms are not macros; there are no
macros. They are a fixed set of built-in syntax that desugars to ordinary struct expressions and,
for steps, to a call of `push_step`. Each form has exactly one delimiter, and the delimiter says
its shape:

#table(
  columns: (auto, 1fr, auto),
  [Delimiter], [Shape], [Example],
  [`name!(…)`], [attributes, then a fixed number of elements], [`s!`: at most one `t![…]`],
  [`name![…]`], [elements only, any number, no attributes], [`t![…]`],
  [`name!{…}`], [attributes, then any number of elements], [`choice!{…}`],
)

Attributes are `key = expr`, separated by commas, and always come before the elements. Optional
attributes may be omitted.

The one primitive that suspends is `push_step` in `std::narrative`, a built-in
`pushdown fn push_step<S: Step>(s: S) -> S::Output`. `s!` is an ordinary step. Its attributes,
all optional, are `who` (the speaker's display text; absent means narration), `voice` and
`render`, and its one optional element is the text. There is one speaker per step. `s!()` waits
without a message. The form has value `()`:

```rust
s!(who = "Azusa", voice = AZUSA_0072, render = r, t!["ぬっ"]);
// is
push_step(Say {
    who: Some("Azusa"),
    voice: Some(AZUSA_0072),
    render: Some(r),
    text: Some(t!["ぬっ"]),
});
```

`choice!{…}` is one step. Its attributes are `id`, a string literal unique within the function,
and an optional `render`. Its elements are arms `t![…] => V` or `t![…] if cond => V`, separated
by commas; an arm with a guard is shown only when `cond` holds. All variants come from one
author-declared enum without payloads, each at most once. The form evaluates to the selected
variant, and branching is an ordinary exhaustive `match` on it, so arms are data, not code blocks.

`t![…]` builds a `Text` value (rich text). Its items are juxtaposed, without commas, and
concatenate directly:

- a string literal with Rust escapes; the text is exactly its content, and a line break is `\n`;
- ruby: `["数多"]("あまた")` for group ruby, `["漢字"]("かん"|"じ")` for mono ruby, where the
  number of reading parts equals the number of base characters;
- a text represent value: `!["赤い"](color_text(RED))`. The target is a constant expression of
  type `TextEffect` (tentative name), folded at compile time. It is a value, not a function, so
  the presentation of text stays as analyzable as the screen. Emphasis is `!["you"](emphasis())`.

```rust
s!(t!["これは" ["数多"]("あまた") "の" !["赤い"](color_text(RED)) "花"]);
```

`#[scene]` marks a `pushdown fn` as a *scene*: the unit of model checking, one RSM component.
Only a scene may call `push_step`, which is impure because it suspends, and only a scene may call
other scenes. Scenes are called with ordinary call syntax (`FestivalHub();`,
`let answer = Confession();`). They call each other directly, without `.await`, like Kotlin
`suspend` functions, which can be called only from other suspending functions @kotlincoroutines;
a step suspends the whole narrative until input. A scene that can end in several ways returns an
enum, and the caller matches on it. The termination check of Section 3.1 applies to scenes.

A `pushdown fn` without `#[scene]` is an *instant procedure*. It has finite types, may read and
write story variables and may call other instant procedures and `const fn`s. It may not call
`push_step` or a scene, may not recurse (the call graph among instant procedures is acyclic) and
has only bounded loops (`for` over a constant range or array; no `loop` or `while`). It therefore
terminates without input by construction, and the analyzer treats a call as one instant
transition inside the calling scene.

=== Node editor as a view

An RSM is literally a node graph: each *component* is a graph with entry and exit nodes, and a
*box* stands for a call whose exits are wired to the caller @alur2005. In Kagari a component is
a `#[scene]` function, a box is a call of a `#[scene]` function, the edges are its structured
control flow, and `s!` and `choice!` steps are input nodes. A node editor that shows scenes as
graphs remains possible, but the XML is no longer a canonical form to round-trip through. The
text is canonical, and it still diffs and merges as text.

#decision[
  Kagari has one Rust-like language with three function kinds: `fn` (Turing-complete, the
  system), `pushdown fn` (the narrative) and `const fn` (renders, constants, tabulated helpers).
  The pushdown restriction is the property of `pushdown fn` and nothing else, checked by the type
  and kind checker. Within it, `#[scene]` marks the unit of model checking: only scenes step and
  call scenes; other `pushdown fn`s are instant procedures. The only channel from `fn` code into
  the narrative is starting an `#[entry]` scene with finite arguments; the only channels back are
  its return value and write-only meta. Narrative forms (`s!`, `choice!`, `t!`) are fixed
  built-in sugar for struct expressions and `push_step`, allowed in `.kix`. `.kis` and `.kix`
  text is canonical in version control; a node editor, if built, is a view of it.
]

// ================================================================
= Presentation as a function of state

== Where the φ problem comes from

Imperative commands such as `show bg roof` assign hidden presentation variables. At a point where
two branches merge, those variables need a φ-node, exactly as in SSA construction @cytron1991.
If the φ is left implicit, the screen depends on the _path_, not on $sigma$, and
$f("pos", sigma)$ is no longer well defined.

#figure(
  diagram(
    ..fd,
    spacing: (6mm, 8mm),
    node((1, 0), [choice 7], name: <c7>, fill: soft),
    node((0, 1), align(center)[7a \ #small[`show bg school_roof`]], name: <a>),
    node((2, 1), align(center)[7b \ #small[`show bg classroom`]], name: <b>),
    node((1, 2), align(center)[line 412: `say …` \ #small[$"bg" = phi("roof", "classroom")$]], name: <m>, stroke: warn-line + 0.9pt, fill: warn),
    edge(<c7>, <a>, "-|>"),
    edge(<c7>, <b>, "-|>"),
    edge(<a>, <m>, "-|>"),
    edge(<b>, <m>, "-|>"),
    node((2.6, 2), align(left)[#small[Lint: background at line 412 \ is ambiguous: roof via 7a, \ classroom via 7b]], stroke: none),
  ),
  caption: [An implicit φ at a merge point. The fix is either a keyframe after the merge or an
    explicit state variable.],
)

== Three mechanisms, used together

+ *Keyframes and deltas as render functions.* Each step may carry a render, a
  `const fn(Screen) -> Screen` passed as its `render` attribute. The render's only input is the
  screen, and it is a `const fn`, so the compiler evaluates it and each render is fully known at
  compile time. A render whose output does not depend on its input declares the complete screen,
  as in the Elm architecture where the view is a function of the model @czaplicki2013: that is a
  *keyframe*, typically one that starts from `Screen::empty()`. The compiler detects keyframes.
  Any other render is a *delta*. The analogy is a video codec: a keyframe is an I-frame, a delta
  is a P-frame, and seeking means jumping to the nearest preceding I-frame and applying the
  deltas. Every change names its animation: `change(..)` returns a pending change that must be
  used, and `apply_animation` applies it. Animations are not part of the screen state and are
  skipped on replay.
+ *Explicit φ promoted into $sigma$.* If the screen after a merge genuinely depends on the branch,
  that dependency is narrative state and must live in $sigma$, declared by the author or
  materialized by the engine. Liveness analysis keeps it cheap: the variable dies at the next
  keyframe.
+ *Ambiguity as a lint.* Abstract interpretation @cousot1977 over the script computes, for each
  step, the set of possible presentation states (powerset lattice, join = union), per entity and
  component, with one summary per scene. A singleton is fine; anything larger is reported with
  the paths that cause it. Comparing screens needs every component type to have decidable
  equality. Components are structs with structural `Eq`, and Turing-complete code has exact
  numbers (`Rat`, `Decimal`) but no floats, so equality stays decidable. Finiteness needs the
  set of screens to stay bounded: a render that reads a component and computes from it (move 10
  units right) can grow the set on every pass through a loop. Renders are Turing-complete
  `const fn`s, so boundedness is undecidable in general. The rule is therefore evaluation with
  a cap (tentative): the compiler evaluates renders on the screens that reach each step, and if a
  step's set grows past a fixed cap during the fixpoint, the render that grows it is an error.
  This is sound, since accepted programs have exactly the computed sets, but it may reject some
  bounded programs. Rational denominators that grow in a loop are caught the same way.

#decision[
  Presentation is authored as render functions, `const fn(Screen) -> Screen`, over an
  entity–component–system screen: entities are managed by renders, components are structs with
  structural `Eq`, and the systems that animate entities live in the engine. Renders are blind to
  $sigma$ by construction: a `render` attribute is a function pointer, or a non-capturing closure
  that coerces to one, and closures in `pushdown fn` are second-class, so no story variable can
  reach a render. When presentation must depend on the story, the script branches with `if` or
  `match` and passes different renders to the steps in each arm. The narrative core never reads
  the
  screen: `Screen` is not a finite type, so a `pushdown fn` cannot hold one. Because renders are
  Turing-complete, bounded screens are enforced by evaluation with a cap (tentative).
]

```rust
static mut AFFECTION_MIO: Int<0, 5> = 0;

#[scene]
pushdown fn Roof() {
    s!(render = roof_evening, t!["The wind on the roof is cold."]);
    match AFFECTION_MIO {
        3..=5 => s!(who = "Mio", render = |mut screen| {
            screen.entity(MIO).appearance.pose
                .change(MIO::SMILE)
                .apply_animation(fade(10));
            screen
        }, t!["You came."]),
        _ => s!(who = "Mio", render = |mut screen| {
            screen.entity(MIO).appearance.pose
                .change(MIO::NEUTRAL)
                .apply_animation(fade(10));
            screen
        }, t!["Oh. It's you."]),
    }
}

const fn roof_evening(_: Screen) -> Screen {
    let mut screen = Screen::empty();
    screen.background().change(BG::ROOF_EVENING).apply_animation(fade(30));
    screen.entity(HARUKA).appearance.pose
        .change(HARUKA::SMILE)
        .apply_animation(instant_switch());
    screen
}
```

The first render ignores its input screen, so it is a keyframe; the renders in the `match` arms
are deltas, written inline as non-capturing closures.

The ambiguity lint is likely the single most valuable debugging feature. It catches exactly the
class of bug that today "only the author knows about": a sprite left over from another route, BGM
that keeps playing after a merge.

// ================================================================
= Controlling state explosion

Twenty independent three-way choices give $3^(20) approx 3.5 times 10^9$ states; we estimate
that commercial titles such as 君と彼女と彼女の恋。 @kimikano2013 have branching on this scale.
That number only matters if we enumerate states, and we never will.

== Saves and jumps are traces, not states

To show line $X$ we do not need "the state at $X$"; we need _some_ history that reaches $X$, then
a replay. Replaying $delta$ without presentation is cheap (no rendering, no animation, no
asset loading), and $f$ is evaluated once, at the destination.

== Sets of states are symbolic

The set of states that can reach a line is represented as a reduced ordered binary decision
diagram @bryant1986, or a multi-valued decision diagram for enum flags @srinivasan1990. Twenty
independent three-way choices give a diagram with about twenty nodes. Blowup only happens when
flags interact in genuinely complicated ways, and those interactions are what the author needs to
see anyway. Each line in the editor can display its *reachability condition*, for example
$("met"_A and not "met"_B) or "route" = C$.

#figure(
  diagram(
    ..fd,
    spacing: (19mm, 6mm),
    node((0, 0), $c_1$, name: <c1>, shape: circle),
    node((1, 0), $c_2$, name: <c2>, shape: circle),
    node((2, 0), $c_3$, name: <c3>, shape: circle),
    node((3, 0), $dots.c$, name: <dots>, stroke: none),
    node((4, 0), $c_(20)$, name: <c20>, shape: circle),
    node((5, 0), $top$, name: <t>, shape: rect),
    ..for (a, b) in ((<c1>, <c2>), (<c2>, <c3>), (<c3>, <dots>), (<dots>, <c20>), (<c20>, <t>)) {
      (
        edge(a, b, "-|>", bend: 40deg),
        edge(a, b, "-|>"),
        edge(a, b, "-|>", bend: -40deg),
      )
    },
  ),
  caption: [A multi-valued decision diagram for twenty independent three-way choices: 21 nodes
    and 60 edges, against $3^(20)$ leaves for an explicit tree.],
)

== Jumping is witness generation

"Show me line $X$ in the case where Mio's affection is at least 3" is a model-checking query
@baier2008. The decision diagram (or a SAT solver) returns a satisfying assignment and a path
that realizes it, which is then replayed. An unreachable line is dead code and is reported.

== Shrinking the state with dataflow analysis

- *Liveness.* A flag is dead after its last read, so it is projected out of reachable-set
  computations from that point. Interprocedural versions of these analyses are graph
  reachability problems @reps1995.
- *Bisimulation minimization.* States with identical futures are merged by partition
  refinement @paige1987. This is the computable approximation of the Nerode quotient. In
  practice most early flags collapse after a route lock.

== Lazy, incremental evaluation

Nothing above is computed up front. Each analysis is a memoized, demand-driven query such as
"reachable set at node $N$" or "presentation at $N$ under $sigma$", in the style of self-adjusting
computation @acar2005 and Adapton @hammer2014, for which Salsa @salsa is a production
implementation. Editing one scene invalidates only the queries that depend on it, which is what
makes realtime preview affordable while editing.

// ================================================================
= Combinatorial choices: the party problem

At a party the player talks to each of $n$ guests once, in any order. There are $n!$ complete
orderings and $floor(e dot n!)$ ordered prefixes. If the future depends only on _who_ has been
visited, the Nerode state is the visited subset: $2^n$ states, the same compression the
Held–Karp algorithm uses for the travelling salesman problem @heldkarp1962.

#grid(
  columns: (1fr, 1.15fr),
  column-gutter: 8mm,
  align: horizon,
  figure(
    diagram(
      ..fd,
      spacing: (9mm, 9mm),
      node-inset: 4pt,
      node((1, 0), $emptyset$, name: <e>),
      node((0, 1), ${A}$, name: <a>),
      node((1, 1), ${B}$, name: <b>),
      node((2, 1), ${C}$, name: <c>),
      node((0, 2), ${A,B}$, name: <ab>),
      node((1, 2), ${A,C}$, name: <ac>),
      node((2, 2), ${B,C}$, name: <bc>),
      node((1, 3), ${A,B,C}$, name: <abc>, fill: soft),
      edge(<e>, <a>, "-|>"), edge(<e>, <b>, "-|>"), edge(<e>, <c>, "-|>"),
      edge(<a>, <ab>, "-|>"), edge(<a>, <ac>, "-|>"),
      edge(<b>, <ab>, "-|>"), edge(<b>, <bc>, "-|>"),
      edge(<c>, <ac>, "-|>"), edge(<c>, <bc>, "-|>"),
      edge(<ab>, <abc>, "-|>"), edge(<ac>, <abc>, "-|>"), edge(<bc>, <abc>, "-|>"),
    ),
    caption: [Subset lattice for $n = 3$. Each path is one ordering; states are shared.],
  ),
  figure(
    table(
      columns: 4,
      align: (center, right, right, right),
      [$n$], [ordered prefixes], [subsets $2^n$], [counts $n+1$],
      [3], [16], [8], [4],
      [5], [326], [32], [6],
      [8], [109 601], [256], [9],
      [10], [9 864 101], [1 024], [11],
    ),
    caption: [States needed under three assumptions about what the future depends on.],
  ),
)

Further reductions, in order of strength:

- *Independence.* If conversations $A$ and $B$ touch disjoint parts of $sigma$, then $A B$ and
  $B A$ reach the same state. This is the theory of Mazurkiewicz traces @mazurkiewicz1977
  @diekert1995, and partial-order reduction explores one representative per equivalence class
  @valmari1991 @peled1993 @godefroid1996.
- *Symmetry.* If only the _number_ of visited guests matters, there are $n + 1$ states.
- *Symbolically* the set "all subsets of $n$ independent bits" is the constant-true diagram.

== A shuffle operator in the language

The important move is in the language, not the analyzer. A finite or pushdown automaton can
express "each guest exactly once" only by spelling out $2^n$ control states. A *shuffle*
(interleaving) operator stays in the same language class (the shuffle of regular languages is
regular) but is exponentially more succinct @mayer1994. The following is a sketch; `each_once`
is not part of the language yet. It reads like `loop { match choice!{…} {…} }`, except that each
arm is offered at most once:

```rust
enum Guest { Haruka, Mio, Rin, Sensei, Leave }

#[scene]
pushdown fn Party() {
    // Sketch: `each_once` and `visited` are not part of the language yet.
    each_once choice!{
        id = "guest",
        t!["Talk to Haruka"] => Guest::Haruka,
        t!["Talk to Mio"] => Guest::Mio,
        t!["Talk to Rin"] => Guest::Rin,
        t!["Talk to the teacher"] => Guest::Sensei,
        t!["Leave the party"] => Guest::Leave,
    } {
        Guest::Haruka => TalkHaruka(),
        Guest::Mio => TalkMio(),
        Guest::Rin => TalkRin(),
        Guest::Sensei => TalkSensei(),
        Guest::Leave => break,
    }
}
```

The shuffle of context-free languages is not context-free in general @gischer1981, so each
branch must run *atomically*: a conversation is a call that returns before the next one starts.
Order-dependence is then declared rather than discovered:

```rust
#[scene]
pushdown fn TalkMio() {
    if visited(Guest::Haruka) {  // declared dependency on the visited set
        s!(who = "Mio", t!["Haruka told me you'd come."]);
    }
    // …
}
```

The analyzer reads the state as a bitset plus the declared dependencies. It never explores
orderings to find out that they commute.

// ================================================================
= Live preview

#decision[
  Snapshots are taken at choice points and include the screen. Preview restores the nearest
  preceding choice snapshot and re-executes the narrative core to the cursor, running the renders
  on the way without their animations. Locating _which_ line to
  inspect is left to the author, supported by the linter; witness-based jumping (Section 5.3)
  is a later phase.
]

#figure(
  diagram(
    ..fd,
    spacing: (13mm, 8mm),
    node((0, 0), $K_0$, name: <k0>, shape: circle, fill: soft),
    node((1, 0), $K_1$, name: <k1>, shape: circle, fill: soft),
    node((2, 0), $K_2$, name: <k2>, shape: circle, fill: soft),
    node((3.2, 0), [cursor], name: <x>, stroke: accent + 1pt),
    node((4.2, 0), $K_3$, name: <k3>, shape: circle, fill: soft),
    edge(<k0>, <k1>, "-|>", [choice]),
    edge(<k1>, <k2>, "-|>", [choice]),
    edge(<k2>, <x>, "=|>", [replay $delta$ only]),
    edge(<x>, <k3>, "-|>", [choice]),
    node((3.2, 1), [evaluate $f$ once], name: <f>, stroke: none),
    edge(<x>, <f>, "-|>"),
  ),
  caption: [Preview after an edit: restore snapshot $K_2$, replay the narrative core to the
    cursor, render once.],
)

Three details:

- *The snapshot includes the call stack.* After the choice, a `return` must know where to go. Inside
  the hub that is one frame; inside a phone call during stall A on day 2 it is three.
- *Loading and jumping without a snapshot.* The narrative core replays from the start, but renders
  run only from the last keyframe on the path.
- *Hot reload.* When the author edits a function, snapshots after the first edited step on the
  current trace are invalidated and rebuilt by replay, as Inky does after recompiling @inky. If a
  recorded choice no longer exists, preview stops at that choice and highlights it.

// ================================================================
= Saving

== Format

#table(
  columns: (auto, 1fr, auto),
  [Part], [Content], [Role],
  [Trace], [Path of the entry scene and its arguments; sequence of stable choice IDs; step count
    after the last choice; script version hash and PRNG seed], [canonical],
  [Snapshot], [Position, call stack, $sigma$ (function pointers stored by path), promoted φ
    variables, PRNG state, screen], [cache],
)

A choice ID is the path of the enclosing function, the choice's `id` and the name of the selected
variant, for example `story::Confession/confess/Confess::Yes`. Replay supplies the call context,
so a choice `id` needs only be unique within its function. IDs are never line numbers. Renaming a
function, a choice `id` or a variant is a divergence on load and is reported with the ID. A save
is thus a witness of reachability: replaying the trace from the entry scene with the stored
arguments reaches the saved position. Randomness uses a deterministic PRNG whose state is part of
$sigma$, so replay is exact.

== Loading across script versions

#figure(
  diagram(
    ..fd,
    spacing: (12mm, 8mm),
    node((0, 0), [Load], name: <l>, shape: fletcher.shapes.pill),
    node((1.4, 0), [hash matches?], name: <q1>, shape: fletcher.shapes.diamond, fill: soft),
    node((3, 0), [restore snapshot], name: <ok>),
    node((1.4, 1.1), [replay trace on new script], name: <rp>),
    node((1.4, 2.2), [all IDs resolved?], name: <q2>, shape: fletcher.shapes.diamond, fill: soft),
    node((3, 2.2), [rebuild snapshot], name: <rb>),
    node((0, 2.2), align(center)[report divergence \ #small[choice ID + position]], name: <div>, stroke: warn-line + 0.9pt, fill: warn),
    edge(<l>, <q1>, "-|>"),
    edge(<q1>, <ok>, "-|>", [yes]),
    edge(<q1>, <rp>, "-|>", [no]),
    edge(<rp>, <q2>, "-|>"),
    edge(<q2>, <rb>, "-|>", [yes]),
    edge(<q2>, <div>, "-|>", [no], label-side: left),
  ),
  caption: [Loading a save. The snapshot is only trusted when the script is unchanged.],
)

== The meta layer

Persistent cross-playthrough state (unlocks, read-text flags, gallery) lives in a separate outer
layer, declared as `Meta<T>` handles such as `static CLEARED_MIO: Meta<bool> = meta(false);`.
Some titles deliberately make this layer part of the story; 君と彼女と彼女の恋。 is a well-known
example @kimikano2013. The story reads meta only through entry arguments: reading a `Meta<T>` is
`fn`-only, so the system reads it and passes the value when it starts an `#[entry]` scene
(Section 3.4). The save stores the arguments with the trace, and the analyzer quantifies over all
argument values, so it treats them as ordinary finite variables and the debugger lets the author
set them directly. The story writes meta write-only, with `meta.write(v)`. Such writes are not
reverted by load or rewind, and the narrative never observes them within the run.

// ================================================================
= Tooling: making intent checkable

== Lints that need no annotations

#table(
  columns: (auto, 1fr, auto),
  [Lint], [Catches], [Technique],
  [Unreachable node], [Dead lines, impossible route conditions], [pushdown reachability],
  [Ambiguous presentation], [Leftover sprite/BGM/background after a merge], [abstract interpretation],
  [Write-never-read], [Flags that never influence anything], [liveness],
  [Unbounded step], [Loop or cycle of calls without input or bound], [interprocedural fixpoint],
  [Unbounded screens], [Render whose read-modify-write grows a step's screen set past the cap], [const evaluation to a fixpoint],
  [Stuck choice], [Choice reachable with no arm offered], [pushdown reachability],
  [Non-atomic shuffle], [`each_once` branch that can be interrupted mid-way], [call-structure check],
)

Kind violations are not lints. A `pushdown fn` that calls an `fn`, holds a `Vec` or stores a
closure is rejected by the type and kind checker before any analysis runs.

== Contracts

Authors can attach assertions to steps and scenes: "Haruka is on screen here", "this scene
requires `MET_B`", "after the confession, `ROUTE` never changes again". These are temporal-logic
properties @pnueli1977, checked over all reachable states. A failing contract comes with a
counterexample trace, which opens directly in the previewer.

== Why this helps AI agents

An agent fails today because author intent is not written down in a checkable form. With this
model an agent can query reachability conditions, read contracts, run lints, replay
counterexamples, and propose missing contracts ("line 412 is reached with two different
backgrounds; should it have a keyframe?"), instead of guessing.

// ================================================================
= Phased plan

Each phase is usable on its own and does not require the later ones.

#table(
  columns: (auto, 1fr, auto),
  [Phase], [Deliverable], [Unlocks],
  [0], [Parser for `.kis` and `.kix`; type and kind checker; narrative IR (an RSM) and narrative interpreter; trace saves with snapshot cache], [G3],
  [1], [Const evaluation of renders over the ECS screen; keyframe detection; choice-point snapshots with the screen; hot-reload preview], [G1],
  [2], [Explicit-state analyzer for small scripts; unreachable, ambiguity, liveness lints], [G4 (partial)],
  [3], [Symbolic reachability (MDDs); per-line reachability conditions; witness jump; contracts with counterexamples], [G2, G4],
  [4], [Incremental query engine for live analysis; `each_once` with declared dependencies; partial-order reduction], [scale],
)

Phase 2 deliberately starts with explicit-state search: it is simple, it validates the IR, and
for small projects it is fast enough. Phase 3 replaces the backend without changing the lint
interface.

// ================================================================
= Open questions for discussion

#question[
  + *Integer ranges.* `Int<lo, hi>` saturates under `+=` and `-=`, with a warning when the
    analyzer proves a bound is reached. Should affection-like counters get a default range, for
    example a prelude alias, and which one?
  + *Recursion depth.* Allow unbounded recursion (full pushdown) or cap stack depth (finite
    automaton, simpler analysis)? No current use case needs unbounded recursion.
  + *Timed input.* Are auto-advance, timed choices and QTEs events in $Sigma$? A suggestion: a
    step whose output is a finite event enum (for example a selected arm or a timeout), recorded in
    the trace like a choice.
  + *φ policy.* When the ambiguity lint fires, should the editor offer to insert a keyframe, to
    promote a state variable, or both?
  + *Meta layer scope.* The story now reads meta only through entry arguments and writes it
    write-only. Is that enough for titles that make the meta layer part of the story?
  + *Bounded-screen cap.* Which cap, counted per step or per scene? Is rejecting some bounded
    programs acceptable in practice?
  + *Numbers in Turing-complete code.* Literal syntax for Rust integers, `Rat` and `Decimal`;
    overflow behaviour (tentative: overflow in const evaluation is a compile error; at runtime
    undecided); the precision of `Decimal` division.
  + *User traits and generics.* Only the standard traits (`Eq`, `Step`) and const generics for
    `Int<lo, hi>` and std types exist. Do authors need their own traits and generics, and how do
    they interact with kind checking and tabulation?
  + *Text interpolation.* `{expr}` of type `Text` or `Int` inside `t![…]` (tentative). How does
    the backlog record interpolated text?
]

#v(4mm)
#bibliography("refs.bib", title: "References", style: "ieee")
