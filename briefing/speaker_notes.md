# Kupferkanne: win-back discount allocation – speaker notes

## 1. cover: Leadership decision paper

Open with the decision, not the analysis: we ask the leadership team to approve a controlled pilot, not a new playbook. The bars are the finding at today's rates: a thousand euros of discount keeps about 2,465 euros of contribution in At Risk and 1,335 in Hibernating, 1.85 times as much. The deck then shows that most of that gap comes from the rates themselves. Kupferkanne is a fictional brand and the data is synthetic; every figure traces to docs/methodology.md in the public project repository.

## 2. summary: Executive summary

The whole deck on one page. The answer first: test a 15 percent rate for Hibernating in a pilot with holdouts before we change the playbook. Context: the win-back pool is a quarter of our customers but only 2 percent of revenue. Three reasons. The playbook gives its deepest discount, 20 percent, to Hibernating, the segment with the thinnest margin. At today's rates a euro of discount keeps 1.85 times as much contribution in At Risk, but at one common rate only about 1.2 times, so most of the gap is the rates. And these are modelled figures, not measured increments. The pilot with its decision rule comes next, then what we ask you to fix today.

## 3. pool: The win-back pool

Before the problem, the scale. Each bar is the whole customer base, split by segment. On top, the share of customers: the two win-back segments, on the right, are a quarter of everyone, 3,909 of 14,967. Below, the share of revenue: the same two segments shrink to a 2 percent sliver, while Champions grow from about a fifth to seven tenths. The light grey segments are Loyal Customers, Potential Loyalists and Recent Customers. So this is a decision about margin discipline on a small pool, not a growth lever, and the playbook's own budget shares, 7 and 3 percent, keep any move small.

## 4. margin: The problem

The first reason. Each bar is the gross margin on an order before the win-back offer. The coloured part is what stays as contribution after the discount; the light part is what the discount gives away. At Risk keeps about 37 points of every order, Hibernating about 27, because the thinnest margin carries the deepest discount. Across all six segments, margin falls step by step down the composite score. With a percentage discount and unchanged unit cost, contribution is simply margin minus discount, so this is arithmetic, not a model.

## 5. cause: The cause

The cause, in one picture. Each line is a segment; the left dots are a 15 percent discount, the right dots 20 percent. The filled dots are the playbook today: At Risk at 15, Hibernating at 20. Between those two, At Risk retains 1.85 times as much contribution per euro of discount. Read straight down a column instead, at one common rate, and the gap shrinks to about 1.2 times. The steep slopes are the rate; the small vertical gaps are the segment. Swapping the rates reverses the ranking, which is why the first test is Hibernating at 15 percent, the blue ring.

## 6. modelled: The uncertainty

The honest part. Everything so far measures how much margin a euro of discount keeps once an order is placed; it does not tell us whether the discount caused the order. At Risk customers are more engaged, so some would have ordered anyway, while a Hibernating customer is less likely to. Both segments already buy at a discount: the dark bars are the mean discount they get today, and the light part, the offer on top, takes them to roughly 36.8 and 46.5 percent off list, against a deepest observed discount of 55 percent. No campaign cost is in the data and the data is synthetic, so the figures attest to pipeline integrity rather than to a market observation. On an incremental basis the ranking can narrow or even reverse. That is why the recommendation is a test, not a rollout.

## 7. pilot: The pilot

Five groups in two segments; eligible customers are randomised within each segment. In At Risk, the playbook's 15 percent offer against a holdout that gets no win-back discount. In Hibernating, the playbook's 20 percent, the 15 percent we want to test, in blue, and a holdout. What we measure is incremental contribution per euro of discount: every offer group is compared with its own segment's holdout, so we see what the discount adds. The rule is fixed before launch: first we decide the Hibernating rate, then whether each offer pays for itself and, only if the budget is short, whether At Risk goes first. The intervals are 95 percent BCa bootstrap intervals, and an unresolved interval keeps today's playbook. One caveat: stage 2 reads the data that picked the rate, so it leans towards keeping the playbook.

## 8. ask: The ask

Three things to fix today so the pilot can start: how customers split into the five groups, a 15 percent offer and a holdout in At Risk and a 20 percent offer, a 15 percent offer and a holdout in Hibernating; how long we observe them; and how we record contact cost. Over the observation window, contribution counts every assigned customer, at zero for those who place no order. Contact cost matters more than it looks: at a 10 percent reactivation rate, contribution is gone at about 1.49 euros per contact in At Risk and 0.67 in Hibernating. One assumption to confirm as well: whether the budget covers every eligible customer, because that decides which metric stage 1 uses. The downside is bounded: if the pilot is inconclusive, the playbook stays.

## 9. a1: Appendix A1

Reference only. One row per segment, one column per step: gross margin from profit and revenue, minus the discount, gives the points kept; divided by the discount, the contribution per euro of discount. The lower grid is the same per-euro figure at both rates: along the playbook's rates it is 1.85 times, down either column about 1.2 times. The last column is the contact cost at which contribution is gone, which is why the pilot records contact cost.

## 10. a2: Appendix A2

Reference only. The bars share one scale, so the concentration shows directly: Champions are about a fifth of customers and seven tenths of revenue. At Risk and Hibernating together are 3,909 customers, 26.1 percent, and 170,808.74 euros of lifetime spend, 2.0 percent of the revenue base.

## 11. a3: Appendix A3

Reference only. The data is synthetic, so the gradients in margin, discount and order value are properties of the generator: the figures prove the pipeline, not a market. The 646 orders are a known, open reconciliation issue, kept visible on purpose.

## 12. a4: Appendix A4

Reference only. The full decision rule behind the pilot slide, fixed before launch, and the statistics it rests on. Stage 1 decides Hibernating's rate; stage 2 stops any offer that cannot pay for itself and, only if the budget is short, decides whether At Risk goes first. One caveat: stage 2 reads the data that picked the rate, so it leans towards keeping the playbook. The first wave sizes the groups and is excluded from the decision data.
