gap = {"T01":["C","C","C"], "T02":["C","C","C"], "T03":["C","C","M"], "T08":["C","C","C"]}
ctrl= {"T06":["CL","FP","CL"], "T07":["FP","FP","CL"], "T10":["CL","CL","CL"], "T12":["CL","CL","CL"]}
miss=sum(v.count("M") for v in gap.values()); tg=sum(len(v) for v in gap.values())
fp=sum(v.count("FP") for v in ctrl.values()); tc=sum(len(v) for v in ctrl.values())
print("DNA-v3 (gate + no-invented-failmodes + no-hedge):")
print(f"  escaped_defect_rate = {miss}/{tg} = {miss/tg*100:.1f}%   caught: "+" ".join(f"{t}:{v.count('C')}/3" for t,v in gap.items()))
print(f"  false_positive_rate = {fp}/{tc} = {fp/tc*100:.1f}%   clean:  "+" ".join(f"{t}:{v.count('CL')}/3" for t,v in ctrl.items()))
print()
print(f"  {'arm':<20}{'escaped':>10}{'false-pos':>12}")
for n,e,f in [("baseline",41.7,8.3),("DNA-v1 no-gate",0.0,100.0),("DNA-v2 gate",8.3,58.3),("DNA-v3 gate+2",miss/tg*100,fp/tc*100)]:
    print(f"  {n:<20}{e:>9.1f}%{f:>11.1f}%")
