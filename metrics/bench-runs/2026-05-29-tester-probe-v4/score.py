gap = {"T01":["C","C","C"], "T02":["C","M","C"], "T03":["C","C","C"], "T08":["C","C","C"]}
ctrl= {"T06":["CL","CL","CL"], "T07":["CL","CL","CL"], "T10":["CL","FP","CL"], "T12":["CL","CL","CL"]}
miss=sum(v.count("M") for v in gap.values()); tg=sum(len(v) for v in gap.values())
fp=sum(v.count("FP") for v in ctrl.values()); tc=sum(len(v) for v in ctrl.values())
print("DNA-v4 (gate + 2 + already-covered clause):")
print(f"  escaped_defect_rate = {miss}/{tg} = {miss/tg*100:.1f}%   caught: "+" ".join(f"{t}:{v.count('C')}/3" for t,v in gap.items()))
print(f"  false_positive_rate = {fp}/{tc} = {fp/tc*100:.1f}%   clean:  "+" ".join(f"{t}:{v.count('CL')}/3" for t,v in ctrl.items()))
print()
print(f"  {'arm':<22}{'escaped':>10}{'false-pos':>12}")
for n,e,f in [("baseline",41.7,8.3),("DNA-v1 no-gate",0.0,100.0),("DNA-v2 gate",8.3,58.3),("DNA-v3 gate+2",8.3,25.0),("DNA-v4 gate+3",miss/tg*100,fp/tc*100)]:
    print(f"  {n:<22}{e:>9.1f}%{f:>11.1f}%")
