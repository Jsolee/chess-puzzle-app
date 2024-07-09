import React, { useState, useEffect } from 'react';
import { Chessboard } from 'react-chessboard';
import { Chess } from 'chess.js';

const Puzzle = ({ puzzle, onComplete }) => {
  const [game, setGame] = useState(new Chess(puzzle.FEN));
  const [currentMoveIndex, setCurrentMoveIndex] = useState(0);
  const [moveResult, setMoveResult] = useState(null);
  const [boardSize, setBoardSize] = useState(Math.min(window.innerWidth, window.innerHeight) * 0.8);
  const [userElo, setUserElo] = useState(1500); // User's starting ELO
  const [eloChange, setEloChange] = useState(0); // ELO change after each attempt

  useEffect(() => {
    const handleResize = () => {
      setBoardSize(Math.min(window.innerWidth, window.innerHeight) * 0.9);
    };

    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  useEffect(() => {
    const newGame = new Chess(puzzle.FEN);
    setGame(newGame);
    setCurrentMoveIndex(0);
    setMoveResult(null);
    setTimeout(() => makeNextMove(newGame, puzzle.Moves.split(" "), 0), 750);
  }, [puzzle]);

  const calculateEloChange = (isCorrect) => {
    const puzzleElo = puzzle.Rating;
    const puzzleDeviation = puzzle.RatingDeviation;
    const expectedScore = 1 / (1 + 10 ** ((puzzleElo - userElo) / 400));
    const actualScore = isCorrect ? 1 : 0;
    const kFactor = 32; // Basic K-factor, can be adjusted
    return Math.round(kFactor * (actualScore - expectedScore));
  };

  const handleMove = (sourceSquare, targetSquare) => {
    const move = `${sourceSquare}${targetSquare}`;
    const correctMoves = puzzle.Moves.split(" ");
    const correctMove = correctMoves[currentMoveIndex];
    const isCorrect = move === correctMove;

    if (isCorrect) {
      game.move({ from: sourceSquare, to: targetSquare });
      setMoveResult('correct');
      const nextMoveIndex = currentMoveIndex + 1;
      setCurrentMoveIndex(nextMoveIndex);

      if (nextMoveIndex === correctMoves.length) {
        setTimeout(onComplete, 1500); // Move to next puzzle after 1 second
      } else {
        setTimeout(() => makeNextMove(game, correctMoves, nextMoveIndex), 750); // Make the next move automatically after 0.5 second
      }
    } else {
      setMoveResult('incorrect');
    }

    const change = calculateEloChange(isCorrect);
    setUserElo(userElo + change);
    setEloChange(change);
    setTimeout(() => setMoveResult(null), 1500); // Hide message after 1 second
  };

  const makeNextMove = (game, correctMoves, moveIndex) => {
    const nextMove = correctMoves[moveIndex];
    const from = nextMove.slice(0, 2);
    const to = nextMove.slice(2, 4);

    console.log(`Making next move: ${from} to ${to}`); // Debugging information

    const move = game.move({ from, to });
    if (move) {
      setCurrentMoveIndex(moveIndex + 1);

      if (moveIndex + 1 === correctMoves.length) {
        setTimeout(onComplete, 1500); // Move to next puzzle after 1 second
      }
    } else {
      console.error(`Invalid move: { from: ${from}, to: ${to} }`); // Debugging information
    }
  };

  const orientation = game.turn() === 'w' ? 'white' : 'black';

  return (
    <div>
      <h2>Puzzle ID: {puzzle.PuzzleId}</h2>
      <div
      style={{
        marginTop: '5px',
        fontSize: `${boardSize * 0.025}px`,
      }}>User ELO: {userElo} | Puzzle ELO: {puzzle.Rating}</div>
      {moveResult && (
        <div>ELO Change: {eloChange > 0 ? `+${eloChange}` : eloChange}</div>
      )}
      <div style={{ height: `${boardSize + 50}px` }}>
      <div style={{ position: 'relative' }}>
        <Chessboard
          position={game.fen()}
          orientation={orientation}
          boardWidth={boardSize}
          onPieceDrop={(sourceSquare, targetSquare) => {
            handleMove(sourceSquare, targetSquare);
            return false;
          }}
        />
        <div style={{
        position: 'absolute',
        top: `${boardSize * 0.03}px`, // Example: 5% from the top of the board
        right: `${-boardSize * 0.1}px`, // Example: 15% to the left from the right edge of the board
        width: `${boardSize * 0.05}px`, // Example: 5% of board size
        height: `${boardSize * 0.05}px`, // Example: 5% of board size
        borderRadius: '50%',
        backgroundColor: game.turn() === 'w' ? 'white' : 'black',
        border: '2px solid black', // Added border
      }}></div>
    </div>
      {moveResult && (
        <div
          style={{
            color: moveResult === 'correct' ? 'green' : 'red',
            marginTop: '10px',
            fontSize: `${boardSize * 0.05}px`,
          }}
        >
          {moveResult === 'correct' ? 'Correct move!' : 'Incorrect move!'}
        </div>
      )}
    </div>
    </div>
  );
};

export default Puzzle;