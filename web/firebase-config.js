// Firebase configuration for web platform
// This file will be used to initialize Firebase for the web version of EchoPost

// Import the functions you need from the SDKs you need
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.7.1/firebase-app.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/10.7.1/firebase-auth.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore.js";

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
	apiKey: "AIzaSyB9d5C1q_JTtHVr6ybQUB_Jk-PbcXO75sA",
	authDomain: "echopost-f0b99.firebaseapp.com",
	projectId: "echopost-f0b99",
	storageBucket: "echopost-f0b99.firebasestorage.app",
	messagingSenderId: "794380832661",
	appId: "1:794380832661:web:cdd40c366274d8cb9bb09c",
	measurementId: "G-3VXNZTJ2GJ",
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

// Export for use in Flutter web
window.firebaseApp = app;
window.firebaseAuth = auth;
window.firebaseFirestore = db;

console.log("Firebase initialized for EchoPost Web");
