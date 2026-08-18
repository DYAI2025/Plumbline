# DNA-v2 verdicts (3 runs/task)
gap = {"T01":["C","C","C"], "T02":["C","C","M"], "T03":["C","C","C"], "T08":["C","C","C"]}
ctrl= {"T06":["CL","CL","FP"], "T07":["CL","CL","FP"], "T10":["FP","FP","FP"], "T12":["CL","FP","FP"]}
miss=sum(v.count("M") for v in gap.values()); tg=sum(len(v) for v in gap.values())
fp=sum(v.count("FP") for v in ctrl.values()); tc=sum(len(v) for v in ctrl.values())
print("DNA-v2 (boundary gate):")
print(f"  escaped_defect_rate = {miss}/{tg} = {miss/tg*100:.1f}%   per-task caught: "+
      " ".join(f"{t}:{v.count('C')}/3" for t,v in gap.items()))
print(f"  false_positive_rate = {fp}/{tc} = {fp/tc*100:.1f}%   per-task clean:  "+
      " ".join(f"{t}:{v.count('CL')}/3" for t,v in ctrl.items()))
print()
print("3-way comparison (lower is better on BOTH):")
print(f"  {'arm':<18}{'escaped':>10}{'false-pos':>12}")
for name,e,f in [("baseline",41.7,8.3),("DNA-v1 (no gate)",0.0,100.0),("DNA-v2 (gate)",miss/tg*100,fp/tc*100)]:
    print(f"  {name:<18}{e:>9.1f}%{f:>11.1f}%")
