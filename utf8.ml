exception MalFormed

let width = Array.make 256 (-1)
let () =
  for i = 0 to 127 do width.(i) <- 1 done;
  for i = 192 to 223 do width.(i) <- 2 done;
  for i = 224 to 239 do width.(i) <- 3 done;
  for i = 240 to 248 do width.(i) <- 4 done

let next s i =
  match s.[i] with
    | '\000'..'\127' as c ->
        Char.code c
    | '\128'..'\223' as c ->
	let n1 = Char.code c in
	let n2 = Char.code s.[i+1] in
        if (n2 < 128) || (n2 > 191) then raise MalFormed;
        let p = ((n1 land 0b11111) lsl 6) lor (n2 land 0b111111) in
        if p < 128 then raise MalFormed;
	p
    | '\224'..'\239' as c ->
	let n1 = Char.code c in
	let n2 = Char.code s.[i+1] in
	let n3 = Char.code s.[i+2] in
        if (n2 < 128) || (n2 > 191) || (n3 < 128) || (n3 > 191) 
	then raise MalFormed;
        let p =
          ((n1 land 0b1111) lsl 12) lor ((n2 land 0b111111) lsl 6) lor
          (n3 land 0b111111)
        in
        if (p < 0x800) || (p >= 0xd800 && p < 0xe000) || 
	  (p >= 0xfffe && p <= 0xffff) then raise MalFormed;
	p
    | '\240'..'\247' as c ->
	let n1 = Char.code c in
	let n2 = Char.code s.[i+1] in
	let n3 = Char.code s.[i+2] in
	let n4 = Char.code s.[i+3] in

        if (n2 < 128) || (n2 > 191) || (n3 < 128) || (n3 > 191) ||
          (n4 < 128) || (n4 > 191) then raise MalFormed;
        let p = ((n1 land 0b111) lsl 18) lor ((n2 land 0b111111) lsl 12) lor
                ((n3 land 0b111111) lsl 6) lor (n4 land 0b111111) in
        if (p < 0x10000) || (p >= 0x110000) then raise MalFormed;
	p
    | _ -> raise MalFormed


let from_stream s =
  match Stream.next s with
    | '\000'..'\127' as c ->
        Char.code c
    | '\128'..'\223' as c ->
	let n1 = Char.code c in
	let n2 = Char.code (Stream.next s) in
        if (n2 < 128) || (n2 > 191) then raise MalFormed;
        let p = ((n1 land 0b11111) lsl 6) lor (n2 land 0b111111) in
        if p < 128 then raise MalFormed;
	p
    | '\224'..'\239' as c ->
	let n1 = Char.code c in
	let n2 = Char.code (Stream.next s) in
	let n3 = Char.code (Stream.next s) in
        if (n2 < 128) || (n2 > 191) || (n3 < 128) || (n3 > 191) 
	then raise MalFormed;
        let p =
          ((n1 land 0b1111) lsl 12) lor ((n2 land 0b111111) lsl 6) lor
          (n3 land 0b111111)
        in
        if (p < 0x800) || (p >= 0xd800 && p < 0xe000) || 
	  (p >= 0xfffe && p <= 0xffff) then raise MalFormed;
	p
    | '\240'..'\247' as c ->
	let n1 = Char.code c in
	let n2 = Char.code (Stream.next s) in
	let n3 = Char.code (Stream.next s) in
	let n4 = Char.code (Stream.next s) in

        if (n2 < 128) || (n2 > 191) || (n3 < 128) || (n3 > 191) ||
          (n4 < 128) || (n4 > 191) then raise MalFormed;
        let p = ((n1 land 0b111) lsl 18) lor ((n2 land 0b111111) lsl 12) lor
                ((n3 land 0b111111) lsl 6) lor (n4 land 0b111111) in
        if (p < 0x10000) || (p >= 0x110000) then raise MalFormed;
	p
    | _ -> raise MalFormed


let compute_len s pos bytes =
  let rec aux n i =
    if i >= pos + bytes then if i = pos + bytes then n else raise MalFormed
    else 
      let w = width.(Char.code s.[i]) in
      if w > 0 then aux (succ n) (i + w) 
      else raise MalFormed
  in
  aux 0 pos

let rec blit_to_int s spos a apos n =
  if n > 0 then begin
    a.(apos) <- next s spos;
    blit_to_int s (spos + width.(Char.code s.[spos])) a (succ apos) (pred n)
  end

let to_int_array s pos bytes =
  let n = compute_len s pos bytes in
  let a = Array.create n 0 in
  blit_to_int s pos a 0 n;
  a

(**************************)

let width_code_point p =
  if p <= 127 then 1
  else if p <= 0x7ff then 2
  else if p <= 0xffff then 3
  else if p <= 0x10ffff then 4
  else raise MalFormed

let store b p =
  (* Adapted from Netstring's netconversion.ml/write_utf8 *)
  if p <= 127 then
    Buffer.add_char b (Char.chr p)
  else if p <= 0x7ff then (
    Buffer.add_char b (Char.chr (0xc0 lor (p lsr 6)));
    Buffer.add_char b (Char.chr (0x80 lor (p land 0x3f)))
  )
  else if p <= 0xffff then (
    (* Refuse writing surrogate pairs, and fffe, ffff *)
    if (p >= 0xd800 & p < 0xe000) or (p >= 0xfffe) 
    then raise MalFormed;
    Buffer.add_char b (Char.chr (0xe0 lor (p lsr 12)));
    Buffer.add_char b (Char.chr (0x80 lor ((p lsr 6) land 0x3f)));
    Buffer.add_char b (Char.chr (0x80 lor (p land 0x3f)))
  )
  else if p <= 0x10ffff then (
    Buffer.add_char b (Char.chr (0xf0 lor (p lsr 18)));
    Buffer.add_char b (Char.chr (0x80 lor ((p lsr 12) land 0x3f)));
    Buffer.add_char b (Char.chr (0x80 lor ((p lsr 6)  land 0x3f)));
    Buffer.add_char b (Char.chr (0x80 lor (p land 0x3f)))
  )
  else raise MalFormed


let from_int_array a apos len =
  let b = Buffer.create (len * 4) in
  let rec aux apos len =
    if len > 0 then (store b a.(apos); aux (succ apos) (pred len))
    else Buffer.contents b in
  aux apos len

let stream_from_char_stream s =
  Stream.from 
    (fun _ ->
       try Some (from_stream s)
       with Stream.Failure -> None)
    