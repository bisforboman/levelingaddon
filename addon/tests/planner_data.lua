-- Quest data for the planner tests: rows cut from a real `collector export` (plannerQuests and
-- plannerZones, QuestieDB 3f10ca0751), with each zone's bands
-- cut down to the quests kept here. Elwynn Forest with Northshire, Duskwood, Redridge, Westfall,
-- Stormwind, and Dun Morogh as a zone that is not next to any of them.
-- Derived from QuestieDB; licensed GPL-3.0.
local _, ns = ...
ns.Data = { plannerQuests = {}, plannerZones = {} }
local t = ns.Data.plannerQuests
t[7]={name="Kobold Camp Cleanup",level=2,req=1,side="alliance",xp=170,pre={783},excl={15},start={{"Marshal McBride",1429,48.92,41.61}},finish={{"Marshal McBride",1429,48.92,41.61}},obj={{"monster","Kobold Vermin",1429,49.17,36.55}}}
t[15]={name="Investigate Echo Ridge",level=3,req=1,side="alliance",xp=250,pre={7},excl={21},start={{"Marshal McBride",1429,48.92,41.61}},finish={{"Marshal McBride",1429,48.92,41.61}},obj={{"monster","Kobold Worker",1429,49.31,34.68}}}
t[18]={name="Brotherhood of Thieves",level=4,req=2,side="alliance",xp=355,pre={783},start={{"Deputy Willem",1429,48.17,42.94}},finish={{"Deputy Willem",1429,48.17,42.94}},obj={{"item","Red Burlap Bandana",1429,53.96,47.03}}}
t[19]={name="Tharil'zun",level=25,req=18,side="alliance",xp=2550,mark="group",preAll={20,98387},start={{"Marshal Marris",1433,28.41,48.97}},finish={{"Marshal Marris",1433,28.41,48.97}},obj={{"item","Tharil'zun's Head",1433,64.36,59.41}}}
t[21]={name="Skirmish at Echo Ridge",level=5,req=1,side="alliance",xp=450,pre={15},excl={54},start={{"Marshal McBride",1429,48.92,41.61}},finish={{"Marshal McBride",1429,48.92,41.61}},obj={{"monster","Kobold Laborer",1429,49,28.35}}}
t[33]={name="Wolves Across the Border",level=2,req=1,side="alliance",xp=170,start={{"Eagan Peltskinner",1429,48.94,40.16}},finish={{"Eagan Peltskinner",1429,48.94,40.16}},obj={{"item","Tough Wolf Meat",1426,28.41,74.35,1429,46.66,43.74}}}
t[54]={name="Report to Goldshire",level=5,req=1,side="alliance",xp=225,pre={21},start={{"Marshal McBride",1429,48.92,41.61}},finish={{"Marshal Dughan",1429,42.11,65.93}}}
t[55]={name="Morbent Fel",level=32,req=20,side="alliance",xp=3850,mark="group",pre={325},start={{"Sven Yorgen",1431,7.78,34.07}},finish={{"Sven Yorgen",1431,7.78,34.07}},obj={{"monster","Morbent Fel",1431,16.9,33.4}}}
t[56]={name="The Night Watch",level=24,req=18,side="alliance",xp=1450,excl={57},start={{"Commander Althea Ebonlocke",1431,73.54,46.82}},finish={{"Commander Althea Ebonlocke",1431,73.54,46.82}},obj={{"monster","Skeletal Warrior",1431,78.63,70.85},{"monster","Skeletal Mage",1431,79.54,71.24}}}
t[57]={name="The Night Watch",level=26,req=18,side="alliance",xp=2100,pre={56},excl={58},start={{"Commander Althea Ebonlocke",1431,73.54,46.82}},finish={{"Commander Althea Ebonlocke",1431,73.54,46.82}},obj={{"monster","Skeletal Fiend",1431,20.65,46.4},{"monster","Skeletal Horror",1431,23.06,47.11}}}
t[58]={name="The Night Watch",level=30,req=18,side="alliance",xp=2450,pre={57},start={{"Commander Althea Ebonlocke",1431,73.54,46.82}},finish={{"Commander Althea Ebonlocke",1431,73.54,46.82}},obj={{"monster","Plague Spreader",1431,23.71,34.07}}}
t[66]={name="The Legend of Stalvan",level=28,req=22,side="alliance",xp=230,excl={67},start={{"Madame Eva",1431,75.79,45.32}},finish={{"Clerk Daltry",1431,72.54,46.87}}}
t[101]={name="The Totem of Infliction",level=25,req=18,side="alliance",xp=2550,start={{"Madame Eva",1431,75.79,45.32}},finish={{"Madame Eva",1431,75.79,45.32}},obj={{"item","Ghoul Fang",1431,26.87,34.28},{"item","Vial of Spider Venom",1431,32.94,39.52},{"item","Skeleton Finger",1431,24.19,43.29}}}
t[163]={name="Raven Hill",level=20,req=17,side="alliance",xp=390,excl={5},start={{"Elaine Carevin",1431,75.34,48.75}},finish={{"Jitters",1431,18.38,56.37}}}
t[164]={name="Deliveries to Sven",level=23,req=17,side="alliance",xp=920,excl={95},start={{"Elaine Carevin",1431,75.34,48.75}},finish={{"Sven Yorgen",1431,7.78,34.07}}}
t[165]={name="The Hermit",level=25,req=17,side="alliance",xp=1000,excl={148},start={{"Elaine Carevin",1431,75.34,48.75}},finish={{"Abercrombie",1431,28.11,31.46}}}
t[169]={name="WANTED: Gath'Ilzogg",level=26,req=15,side="alliance",xp=2650,mark="group",start={{"Wanted: Gath'Ilzogg",1433,24.53,46.16}},finish={{"Magistrate Solomon",1433,24.9,44.45}},obj={{"item","Head of Gath'Ilzogg",1433,64.52,55.79}}}
t[173]={name="Worgen in the Woods",level=28,req=23,side="alliance",xp=1150,excl={221},start={{"Calor",1431,75.75,47.57}},finish={{"Calor",1431,75.75,47.57}},obj={{"monster","Nightbane Shadow Weaver",1431,61.94,52.05}}}
t[174]={name="Look To The Stars",level=25,req=20,side="alliance",xp=2000,excl={175},start={{"Viktori Prism'Antras",1431,79.8,48.02}},finish={{"Viktori Prism'Antras",1431,79.8,48.02}},obj={{"item","Bronze Tube",1413,48.61,84.18,1416,85.95,79.96,1425,34.33,37.76,1426,50.08,49.42,1428,66.06,21.95,1431,77.99,48.33,1434,50.98,35.21,1436,41.27,66.41,1437,10.75,56.75,1441,77.68,77.9,1444,44.81,43.42,1447,45.28,90.95,1452,60.8,38.6,1453,62.43,29.9,1454,75.49,25.36,1455,67.84,42.5,1458,75.48,74.34,2548,78.27,52.64}}}
t[175]={name="Look To The Stars",level=25,req=20,side="alliance",xp=1000,pre={174},excl={177},start={{"Viktori Prism'Antras",1431,79.8,48.02}},finish={{"Blind Mary",1431,81.99,59.09}}}
t[177]={name="Look To The Stars",level=25,req=20,side="alliance",xp=1500,pre={175},excl={181},start={{"Blind Mary",1431,81.99,59.09}},finish={{"Viktori Prism'Antras",1431,79.8,48.02}},obj={{"item","Mary's Looking Glass",1431,80.9,71.96}}}
t[179]={name="Dwarven Outfitters",level=1,req=1,side="alliance",xp=80,start={{"Sten Stoutarm",1426,29.93,71.2}},finish={{"Sten Stoutarm",1426,29.93,71.2}},obj={{"item","Tough Wolf Meat",1426,28.41,74.35,1429,46.66,43.74}}}
t[226]={name="Wolves at Our Heels",level=21,req=19,side="alliance",xp=1250,start={{"Lars",1431,7.71,33.2}},finish={{"Lars",1431,7.71,33.2}},obj={{"monster","Starving Dire Wolf",1431,35.63,24.52},{"monster","Rabid Dire Wolf",1431,33.14,29.35}}}
t[254]={name="Digging Through the Dirt",level=35,req=20,side="alliance",parent=253,start={{"Eliza's Grave Dirt",1431,28.87,30.75}},finish={{"Eliza's Grave Dirt",1431,28.87,30.75}}}
t[783]={name="A Threat Within",level=1,req=1,side="alliance",xp=40,excl={7},start={{"Deputy Willem",1429,48.17,42.94}},finish={{"Marshal McBride",1429,48.92,41.61}}}
t[3100]={name="Simple Letter",level=1,req=1,side="alliance",races={"HUMAN"},classes={"WARRIOR"},xp=40,pre={7},start={{"Marshal McBride",1429,48.92,41.61}},finish={{"Llane Beshere",1429,50.24,42.29}}}
t[3101]={name="Consecrated Letter",level=1,req=1,side="alliance",races={"HUMAN"},classes={"PALADIN"},xp=40,pre={7},start={{"Marshal McBride",1429,48.92,41.61}},finish={{"Brother Sammuel",1429,50.43,42.12}}}
t[5261]={name="Eagan Peltskinner",level=2,req=1,side="alliance",xp=85,pre={783},excl={33},start={{"Deputy Willem",1429,48.17,42.94}},finish={{"Eagan Peltskinner",1429,48.94,40.16}}}
t[92745]={name="The State of the Mines",level=14,req=9,side="alliance",xp=490,preAll={92742,92744},excl={92747},start={{"Alba Fairmoon",1436,52.48,52.97,1453,61.87,30.58}},finish={{"Alba Fairmoon",1436,52.48,52.97,1453,61.87,30.58}},obj={{"monster","Kobold Digger",1436,45.32,20.46},{"monster","Riverpaw Miner",1436,30.26,47.55}}}
t = ns.Data.plannerZones
t[1426]={name="Dun Morogh",min=5,max=30,bands={[1]={179},[2]={179}}}
t[1429]={name="Elwynn Forest",min=2,max=10,bands={[1]={33,783,7,5261,18,15,3100,3101,21,54},[2]={33,783,7,5261,18,15,3100,3101,21,54},[3]={18,21,54}}}
t[1431]={name="Duskwood",min=24,max=30,bands={[4]={163,164,165,56,101,226,174,57,175,58,177,55},[5]={163,164,165,56,101,226,174,66,173,57,175,58,177,55},[6]={163,164,165,56,101,226,174,66,173,57,175,58,177,55},[7]={165,56,101,174,66,173,57,175,58,177,55},[8]={58,55}}}
t[1433]={name="Redridge Mountains",min=14,max=25,bands={[3]={169},[4]={169,19},[5]={169,19},[6]={169,19},[7]={169,19}}}
t[1436]={name="Westfall",min=10,max=18,bands={[2]={92745},[3]={92745},[4]={92745},[5]={92745}}}
t[1453]={name="Stormwind City",min=15,max=55,bands={[2]={92745},[3]={92745},[4]={92745},[5]={92745}}}
