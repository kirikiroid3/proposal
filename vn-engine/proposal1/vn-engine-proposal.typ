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
  #text(9.5pt, fill: luma(100))[Design proposal · draft for team discussion · 16 October 2026, revised 19 October 2026]
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
call stack, flags), and $f$ maps the current position, state and local time $t$ to a screen
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
    presentation is evaluated lazily at the destination. The analyzer works on the same script IR
    as the narrative core.],
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
+ *Reachability queries are decidable*, e.g. "can line 412 be reached with `met_B` unset?"

== What a pushdown language looks like

The program-shaped form of a pushdown system is a *Boolean program* (Ball and Rajamani's SLAM
project @ball2000boolean @ball2000bebop); its graphical twin is a *recursive state machine*
(RSM) @alur2005. In VN terms:

#figure(caption: [Restrictions that keep the script language a pushdown system.], table(
  columns: (1fr, 1fr),
  align: left,
  [Allowed], [Forbidden (and why)],
  [Global and scene-local variables of finite type: `bool`, enums, `int` in a declared range],
  [Unbounded integers, runtime strings, lists, maps: they reintroduce counters, hence Turing completeness],
  [`call scene` / `return`, including recursion],
  [Scenes as first-class values, closures: higher-order pushdown systems are decidable but far more expensive to analyze],
  [Computed call over a _finite enum_ of scenes (a case split)],
  [Jumping into the middle of another scene: breaks well-nested call/return],
  [`jump` within the current scene; loops that pass through a `choice` or have a fixed bound],
  [Loops, or cycles of calls, with no input and no bound: a single step might not terminate],
  [`choice` (input), `say` / `show` (output via the presentation layer)],
  [Reading wall-clock time or OS state inside the narrative core (see the meta layer, Section 8.3)],
))

A stack frame is a return address plus the caller's locals. Both are finite, so the stack
alphabet is finite: that is exactly the definition of a pushdown system.

== When the stack matters: the 学園祭 example

The basic festival hub does *not* need a stack. The player goes from the campus map to stall A, B
or C, the story plays, and control always returns to the same place, the map. A revisited stall
prints a short message and returns. The only memory is the position and three `visited` bits,
so this is a finite automaton.

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
    edge(<map>, <end>, "-|>", [`visited_A ∧ visited_B ∧ visited_C`], label-side: right),
  ),
  caption: [The single-day hub. Every stall returns to the same node, so a plain `jump` suffices.
    The state space is 5 control nodes $times$ $2^3$ flag values.],
)

The stack becomes useful when one sub-scene is entered from different places and must return to
different places:

- *Reused hub.* The festival runs on day 1 (afterwards: dorm) and day 2 (afterwards: ending check).
- *Interrupts.* A phone call can happen inside any stall or on the map, and afterwards the game resumes exactly where it was.

#figure(
  diagram(
    ..fd,
    spacing: (16mm, 8mm),
    node((0, 0), [`day1`], name: <d1>),
    node((1, 0), [box: `festival_hub`], name: <b1>, fill: soft),
    node((3, 0), [`dorm_night`], name: <dn>),
    node((0, 3), [`day2`], name: <d2>),
    node((1, 3), [box: `festival_hub`], name: <b2>, fill: soft),
    node((3, 3), [`ending_check`], name: <ec>),
    edge(<d1>, <b1>, "-|>"),
    edge(<d2>, <b2>, "-|>"),
    node((-0.2, 1.5), text(8pt, fill: accent)[component \ `festival_hub`], name: <lbl>, stroke: none),
    node((1, 1.5), [entry], name: <en>, shape: fletcher.shapes.pill),
    node((2, 1.5), [map ⇄ stalls], name: <hub>),
    node((3, 1.5), [exit], name: <ex>, shape: fletcher.shapes.pill),
    edge(<en>, <hub>, "-|>"),
    edge(<hub>, <ex>, "-|>"),
    node(enclose: (<lbl>, <en>, <hub>, <ex>), inset: 6pt, stroke: (paint: accent, dash: "dashed"), corner-radius: 6pt),
    edge(<b1>, <en>, "--|>", [call: push `day1`], label-side: left),
    edge(<b2>, <en>, "--|>", [call: push `day2`], label-side: right),
    edge(<ex>, <dn>, "--|>", [return: pop], label-side: right),
    edge(<ex>, <ec>, "--|>", [return: pop], label-side: left),
  ),
  caption: [A recursive state machine. Boxes are calls into another component; the stack
    remembers which box to return to. Without the stack, `festival_hub` would have to be
    duplicated once per caller.],
) <fig-rsm>

#decision[
  Adopt the pushdown model. Its practical value is *succinctness*: with bounded call depth it
  recognizes exactly what a finite automaton does, but a finite automaton would need one copy of
  each shared scene per call site, and with nesting the copies multiply. With unbounded recursion
  it gains genuine context-free power at no cost to decidability.
]

```xml
<scene name="day1">
  ...
  <call scene="festival_hub" />
  <call scene="dorm_night" />
</scene>

<scene name="festival_hub">
  <label id="map" />
  <choice id="map">
    <choice-arm id="a" text="Go to A"><call scene="stall_a" /><goto label="map" /></choice-arm>
    <choice-arm id="b" text="Go to B"><call scene="stall_b" /><goto label="map" /></choice-arm>
    <choice-arm id="c" text="Go to C"><call scene="stall_c" /><goto label="map" /></choice-arm>
    <match vars="visited_a visited_b visited_c">
      <cases><case val="true true true" /><do><choice-arm id="leave" text="Leave" /></do></cases>
      <cases><case val="_ _ _" /><do /></cases>
    </match>
  </choice>
</scene>

<scene name="stall_a">
  <match var="visited_a">
    <cases><case val="true" /><do><s>The stall is already packing up.</s><return /></do></cases>
    <cases><case val="false" /><do /></cases>
  </match>
  <set var="visited_a" val="true" />
  ...
</scene>
```

== XML script, node editor as a view

An RSM is literally a node graph: each *component* is a graph with entry and exit nodes, and a
*box* stands for a call whose exits are wired to the caller @alur2005. The script is written as
XML (`.kis`, specified in the Kagari syntax book), as in the example above: `<scene>` is a
component, `<call>` a box, `<goto>` and `<label>` are edges inside a component, and `<s>` and
`<choice>` are input nodes. Exits are not wired separately: a scene that can end in several ways
(a confession that is `accepted` or `rejected`) sets an enum before it returns, and the caller
branches on it.

#decision[
  The XML text is canonical in version control: it diffs and merges as text, and a schema checks
  its structure before any analysis runs. A visual node editor is a view of the XML that
  round-trips through it, not a separate language.
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

+ *Keyframes and deltas as render functions.* Each step may carry a render function
  $"Screen" -> "Screen"$. A render reads only constants and its input screen, never $sigma$, and
  every function it calls has a body the compiler can evaluate, so each render is fully known at
  compile time. A render whose output ignores its input declares the complete screen, as in the
  Elm architecture where the view is a function of the model @czaplicki2013: that is a
  *keyframe*. Any other render is a *delta*. The analogy is a video codec: a keyframe is an
  I-frame, a delta is a P-frame, and seeking means jumping to the nearest preceding I-frame and
  applying the deltas. Every change names its animation; animations are not part of the screen
  state and are skipped on replay.
+ *Explicit φ promoted into $sigma$.* If the screen after a merge genuinely depends on the branch,
  that dependency is narrative state and must live in $sigma$, declared by the author or
  materialized by the engine. Liveness analysis keeps it cheap: the variable dies at the next
  keyframe.
+ *Ambiguity as a lint.* Abstract interpretation @cousot1977 over the script computes, for each
  step, the set of possible presentation states (powerset lattice, join = union), per entity and
  component, with one summary per scene. A singleton is fine; anything larger is reported with
  the paths that cause it. Comparing screens needs every component type to have decidable
  equality, and finiteness needs the set of screens to stay bounded: a render that reads a
  component and computes from it (move 10 units right) can grow the set on every pass through a
  loop, so such a render is a compile error unless the analysis proves it bounded.

#decision[
  Presentation is authored as render functions over an entity–component–system screen:
  entities are managed by render code (`.kirp`, or inline `<r>`), components are declared in
  `.kix` and must implement `Eq`, and the systems that animate entities live in the engine.
  Presentation never reads $sigma$; when it must depend on the story, the script branches with
  `<match>` and attaches different renders to the steps in each arm. The narrative core never
  reads presentation state.
]

```xml
<s>
  <r>
    let screen = Screen::empty();
    screen.background().change(BG::ROOF_EVENING).apply_animation(fade(30));
    screen.entity(HARUKA).appearance.pose.change(HARUKA::SMILE).apply_animation(instant_switch());
    screen
  </r>
  The wind on the roof is cold.
</s>
<match var="affection_mio">
  <cases><case val="3..=5" /><do>
    <s><r>screen.entity(MIO).appearance.pose.change(MIO::SMILE).apply_animation(fade(10));</r>"You came."</s>
  </do></cases>
  <cases><case val="_" /><do>
    <s><r>screen.entity(MIO).appearance.pose.change(MIO::NEUTRAL).apply_animation(fade(10));</r>"Oh. It's you."</s>
  </do></cases>
</match>
```

The first render ignores its input screen, so it is a keyframe; the renders in the `<match>` arms
are deltas.

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
regular) but is exponentially more succinct @mayer1994:

```
scene party:
  each_once until leave_party:
    talk(haruka)
    talk(mio)
    talk(rin)
    talk(sensei)
```

The shuffle of context-free languages is not context-free in general @gischer1981, so each
branch must run *atomically*: a conversation is a call that returns before the next one starts.
Order-dependence is then declared rather than discovered:

```
scene talk_mio:
  if visited(haruka):        # declared dependency on the visited set
    say "Haruka told me you'd come."
  ...
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

Two details:

- *The snapshot includes the call stack.* After the choice, a `return` must know where to go. Inside
  the hub that is one frame; inside a phone call during stall A on day 2 it is three.
- *Loading and jumping without a snapshot.* The narrative core replays from the start, but renders
  run only from the last keyframe on the path.
- *Hot reload.* When the author edits a node, snapshots after the first edited node on the current
  trace are invalidated and rebuilt by replay, as Inky does after recompiling @inky. If a recorded
  choice no longer exists, preview stops at that choice and highlights it.

// ================================================================
= Saving

== Format

#table(
  columns: (auto, 1fr, auto),
  [Part], [Content], [Role],
  [Trace], [Sequence of stable choice IDs, plus script version hash and PRNG seed], [canonical],
  [Snapshot], [Position, call stack, $sigma$, promoted φ variables, PRNG state, screen], [cache],
)

Choice IDs are stable identifiers assigned when a choice node is created, never line numbers.
Randomness uses a deterministic PRNG whose state is part of $sigma$, so replay is exact.

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
layer: a parameter the run reads at start and writes at defined points. Some titles deliberately
make this layer part of the story; 君と彼女と彼女の恋。 is a well-known example @kimikano2013.
For such games the meta layer is part of the semantics, so the analyzer treats its fields as
ordinary finite variables and the debugger lets the author set them directly.

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
  [Unbounded screens], [Render whose read-modify-write grows the screen set in a loop], [abstract interpretation],
  [Stuck choice], [Choice reachable with no arm offered], [pushdown reachability],
  [Non-atomic shuffle], [`each_once` branch that can be interrupted mid-way], [call-structure check],
)

== Contracts

Authors can attach assertions to nodes: "Haruka is on screen here", "this scene requires
`met_B`", "after the confession, `route` never changes again". These are temporal-logic
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
  [0], [XML script (`.kis`) compiled to an RSM IR; narrative interpreter; trace saves with snapshot cache], [G3],
  [1], [Render functions (`.kirp`) over an ECS screen with `.kix` components; keyframe detection; choice-point snapshots with the screen; hot-reload preview], [G1],
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
  + *Integer ranges.* The syntax book makes bounded integers saturate, with a warning when the
    analyzer proves a bound is reached. What default range do affection counters get?
  + *Recursion depth.* Allow unbounded recursion (full pushdown) or cap stack depth (finite
    automaton, simpler analysis)? No current use case needs unbounded recursion.
  + *Timed input.* Are auto-advance, timed choices and QTEs events in $Sigma$? If so, how are
    they recorded in traces?
  + *φ policy.* When the ambiguity lint fires, should the editor offer to insert a keyframe, to
    promote a state variable, or both?
  + *Choice IDs.* Generated identifiers or author-chosen names? Generated IDs are stable under
    renaming; names are readable in divergence reports.
  + *Meta layer scope.* Which meta fields may the narrative core read, and at which points may
    it write them?
]

#v(4mm)
#bibliography("refs.bib", title: "References", style: "ieee")
