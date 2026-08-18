arm = {"o1":"v4","o2":"baseline","o3":"baseline","o4":"v4","o5":"baseline","o6":"v4"}
# per diff: label -> (defects_caught 0-3, verdict)
data = {
 "A": {"o1":(1,"SHIP"),"o2":(2,"SHIP"),"o3":(2,"BLOCK"),"o4":(2,"BLOCK"),"o5":(2,"BLOCK"),"o6":(2,"BLOCK")},
 "B": {k:(3,"BLOCK") for k in ["o1","o2","o3","o4","o5","o6"]},
 "C": {"o1":(3,"BLOCK"),"o2":(3,"BLOCK"),"o3":(3,"BLOCK"),"o4":(3,"BLOCK"),"o5":(2,"BLOCK"),"o6":(2,"BLOCK")},
}
agg={"baseline":[0,0,0],"v4":[0,0,0]}  # caught, total_defects, blocks
runs={"baseline":0,"v4":0}
for D,labels in data.items():
    for lab,(c,v) in labels.items():
        a=arm[lab]; agg[a][0]+=c; agg[a][1]+=3; agg[a][2]+= (1 if v=="BLOCK" else 0); runs[a]+=1
for a in ("baseline","v4"):
    c,t,b=agg[a]
    print(f"{a:9}: non-wiring defect recall = {c}/{t} = {c/t*100:.1f}%   block-rate = {b}/{runs[a]}")
print()
print("per-diff defect recall (caught/9 each):")
for D,labels in data.items():
    bc=sum(labels[l][0] for l in labels if arm[l]=="baseline"); vc=sum(labels[l][0] for l in labels if arm[l]=="v4")
    print(f"  diff {D}: baseline {bc}/9  v4 {vc}/9")
