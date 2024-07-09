import React, { useState, useEffect } from 'react';
import Puzzle from './components/Puzzle';
import puzzles from './puzzles.json';

const App = () => {
  const [currentPuzzle, setCurrentPuzzle] = useState(null);

  useEffect(() => {
    loadRandomPuzzle();
  }, []);

  const loadRandomPuzzle = () => {
    const randomIndex = Math.floor(Math.random() * puzzles.length);
    setCurrentPuzzle(puzzles[randomIndex]);
  };

  const handleComplete = () => {
    loadRandomPuzzle();
  };

  return (
    <div>
      <h1>Chess Puzzle Game</h1>
      {currentPuzzle && <Puzzle puzzle={currentPuzzle} onComplete={handleComplete} />}
    </div>
  );
};

export default App;
