we have two files 
1. prepare_ligands.py 

```shell
chmod +x prepare_ligands.py
python3 prepare_ligands.py smiles.txt X Y Z
```

2. automate_ligand_preparation.sh
```shell
chmod +x ./automate_ligand_preparation.sh
./automate_ligand_preparation.sh smiles.txt X Y Z
```


first run one of theme 
next run the dock all ligands.sh
```shell
chmod +x ./dock_all_ligands.sh
./dock_all_ligands
```
to dock for you 

don't forget to copy the receptor related files to the directory that you wanted

save the smiles in the `smiles.txt`
    for example : COC(=O)Nc1nc2cc(C(=O)c3ccccc3)ccc2[nH]1 mebendazole
                  COC(=O)Nc1nc2cc(C(=O)c3ccccc3)ccc2[nH]1 mebendazole
                  Smiles nameofthecompound


this repo will be updated soon 