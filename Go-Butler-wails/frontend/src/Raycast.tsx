import React, { useState, useEffect } from 'react';
import { Command } from 'cmdk';
import { EventsOn } from '../wailsjs/runtime';

const Raycast: React.FC = () => {
  const [open, setOpen] = useState(true);
  const [query, setQuery] = useState('');

  useEffect(() => {
    // const handler = (e: KeyboardEvent) => {
    //   if (e.ctrlKey && e.key === 'k') {
    //     setOpen((o) => !o);
    //   }
    // };
    // window.addEventListener('keydown', handler);
    // return () => window.removeEventListener('keydown', handler);
    EventsOn("FetchEvent", (e: JSON) => {
      console.log("FetchEvent received:", e);
      // Handle the event as needed
    });
  }, []);

  if (!open) return null;

  return (
    <div
      className="
        fixed top-1/4 left-1/2
        transform -translate-x-1/2
        w-[600px] max-w-full
        bg-[#1e1e1e]
        rounded-2xl
        shadow-2xl
        ring-1 ring-black ring-opacity-50
        text-white
        font-sans
        z-50
      "
      role="dialog"
      aria-modal="true"
      aria-label="Raycast Command Palette"
    >
      <Command
        value={query}
        onValueChange={setQuery}
        className="p-4"
      >
        <Command.Input
          placeholder="Type a command or search…"
          className="
            w-full
            bg-[#2a2a2a]
            rounded-md
            border border-transparent
            px-4 py-3
            text-white
            placeholder-white/50
            focus:outline-none
            focus:ring-2
            focus:ring-[#0a84ff]
            focus:border-transparent
            text-lg
          "
          autoFocus
        />
        <Command.List
          className="
            max-h-72
            overflow-y-auto
            mt-3
            rounded-md
            bg-[#1e1e1e]
          "
        >
          {query === '' ? (
            <>
              <Command.Item
                value="open-file"
                className="cursor-pointer px-4 py-3 rounded-md hover:bg-[#0a84ff]/20 data-[selected]:bg-[#0a84ff]/40"
              >
                📂 Open File
              </Command.Item>
              <Command.Item
                value="search-web"
                className="cursor-pointer px-4 py-3 rounded-md hover:bg-[#0a84ff]/20 data-[selected]:bg-[#0a84ff]/40"
              >
                🌐 Search Web
              </Command.Item>
              <Command.Item
                value="settings"
                className="cursor-pointer px-4 py-3 rounded-md hover:bg-[#0a84ff]/20 data-[selected]:bg-[#0a84ff]/40"
              >
                ⚙️ Settings
              </Command.Item>
            </>
          ) : (
            <Command.Empty className="p-4 text-center text-white/50">
              No results found.
            </Command.Empty>
          )}
        </Command.List>
      </Command>
    </div>
  );
};

export default Raycast;
