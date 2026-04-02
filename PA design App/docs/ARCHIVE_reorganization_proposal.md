I want to re-ogranize the app as below.
Separate wired working design flow and independent calculation modules. This means the sections "Data Manager", "RF tools", "AI Agents", "Knowledge base", "Settings" will be arranged as tabs on top status bar with expanding to their corresponding child pages.
This way it will be clear for the user to clearly differentiate between design flow (Vertical leftmost sidebar) and utilities (Top utility bar). It is like a virtual matrix.
Left sidebar elements, tabs, calculations are dependent on each other. Where are items in top tabs will be used but are not wired to the app. A clone of these will be later used to wire in the respective subtabs of left sidebar.

Plan data organization, database, metadata, tags.. accordingly

Coming to the left sidebar organization, I want it as below
I want to take insipiration (not follow exactly) from the Atomic to Cosmic RF view notes
 Arrange the app such that we start with 
2 First principles (Atom level): Here we define a canvas and simulation engine to simulate basic structures and understand atomic level interactions and its consequences on RF
   2.1 Atoms, electrons, charge and molecules
   2.2 EM waves origin and their propogation mechanism 
   2.3 RF materials and constraints
   2.4 Transmission lines and waveguides, return paths with simple examples    
   2.5 Impact of temperature on various technologies  
       
3 System level
   3.2 Frequency planning
   3.2 Transmitter architectures, design contraints and Theoretical calculations (create appropriate subsections/tabs)
   3.3 Reciver architectures, design constraints and Theoretical calculations (create appropriate subsections/tabs)
   3.4 Link Budget calculations (Move current link budget calculations here)
   3.5 System architecture
	   
4 Technology level
   4.1 Gurard rails, (Move current guardrails here)
   4.2 Device library (Move current guardrails here)
   4.3 Technology stack (PCB,...)   
   4.4 Portfolio generation
	   
5 Device level
    5.1 PA line-up calculations (Move Specifications & Theortical calculations)
	5.2 Architecture development & design choices
	5.3 Transistor design (LP Performance, linearity, stability)
	5.4 PA design (Driver, Main, Aux)-(Performance, linearity, stability)
	5.5 Interstage design and passive (Splitter, combiner)
6 Product level
    6.1 Design
        6.1.1 Doherty design (Final stage) - (Performance, linearity, stability)
	    6.1.2 Line-up Design (Full lineup simulations) - (optimization, Performance, linearity, stability)
		6.2.2 Reliability & Thermal analysis
     6.2 Prototype 
        6.2.1 Test structures        
	    6.2.2 Layout
	    6.2.3 Tapeout 
	    6.2.4 Assembly
		6.2.5 BOM
     6.3 CV measurements
	    6.3.1 DC
		6.3.2 S-parameter
		6.3.3 Loadpull
		6.3.4 RF large-signal performance
		6.3.5 DPD linearity
	6.4 Compare simulation vs measurements
	6.5 Model
	6.6 Compliance matrix
	6.7 Lessons learnt
7. Lessons learnt
8. Reporting
9. App download


The idea is to drive the app in a way that follows more or less the practical design flow so that it is educative, puroseful and practical at the same time.
Please plan a flexible reporting approach at every stage. There is a need to have indivudual report at some stages but finally a master report is also needed that covers in a logical flow all the stages.
The goal is also to have a dedicated version of the app development/download (9.App download) with a dedicated dataset of the finalized design. This will be a dynamic report in itself for a specific design/dataset.
Also think in a way such that any part of the app can be resued or downloaded to make a sub-app for dedicated activity or to create a new app for other designs (Antenna, Mixer, LNA, oscillator... other stages in the line-up)
Review the current app in this context and give me your proposal for app re-organization. You do not necessarily need to follow the numbering given above. You may chose to merge some of them by creating sub-tabs wherever required.
We will then start working to develop further.			
	
		
             	   