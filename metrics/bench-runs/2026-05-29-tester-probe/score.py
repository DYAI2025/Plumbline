arm = {"o1":"dna","o2":"baseline","o3":"baseline","o4":"dna","o5":"baseline","o6":"dna"}
gap = {"T01","T02","T03","T08"}; ctrl = {"T06","T07","T10","T12"}
# verdicts per task per label (CAUGHT/MISSED for gap; CLEAN/FP for control)
V = {
 "T01": dict(o1="CAUGHT",o2="CAUGHT",o3="CAUGHT",o4="CAUGHT",o5="CAUGHT",o6="CAUGHT"),
 "T02": dict(o1="CAUGHT",o2="MISSED",o3="CAUGHT",o4="CAUGHT",o5="MISSED",o6="CAUGHT"),
 "T03": dict(o1="CAUGHT",o2="CAUGHT",o3="CAUGHT",o4="CAUGHT",o5="CAUGHT",o6="CAUGHT"),
 "T08": dict(o1="CAUGHT",o2="MISSED",o3="MISSED",o4="CAUGHT",o5="MISSED",o6="CAUGHT"),
 "T06": dict(o1="FP",o2="CLEAN",o3="CLEAN",o4="FP",o5="CLEAN",o6="FP"),
 "T07": dict(o1="FP",o2="CLEAN",o3="CLEAN",o4="FP",o5="CLEAN",o6="FP"),
 "T10": dict(o1="FP",o2="CLEAN",o3="FP",o4="FP",o5="CLEAN",o6="FP"),
 "T12": dict(o1="FP",o2="CLEAN",o3="CLEAN",o4="FP",o5="CLEAN",o6="FP"),
}
def rate(arm_name):
    miss=tot_g=fp=tot_c=0
    per={}
    for t,labels in V.items():
        for lab,verd in labels.items():
            if arm[lab]!=arm_name: continue
            if t in gap:
                tot_g+=1
                if verd=="MISSED": miss+=1
            else:
                tot_c+=1
                if verd=="FP": fp+=1
        # per-task caught/clean count for this arm
        a=[lab for lab in labels if arm[lab]==arm_name]
        good=sum(1 for lab in a if labels[lab] in ("CAUGHT","CLEAN"))
        per[t]=f"{good}/{len(a)}"
    edr=miss/tot_g*100; fpr=fp/tot_c*100
    return edr,fpr,miss,tot_g,fp,tot_c,per
for A in ("baseline","dna"):
    edr,fpr,miss,tg,fp,tc,per=rate(A)
    print(f"=== {A} ===")
    print(f"  escaped_defect_rate = {miss}/{tg} = {edr:.1f}%   (gap: caught per task " + " ".join(f"{t}:{per[t]}" for t in ['T01','T02','T03','T08']) + ")")
    print(f"  false_positive_rate = {fp}/{tc} = {fpr:.1f}%   (ctrl: clean per task " + " ".join(f"{t}:{per[t]}" for t in ['T06','T07','T10','T12']) + ")")
