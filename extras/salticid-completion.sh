# bash completion for salticid
_salticid_complete() {
  local cur goals

  COMPREPLY=()
  cur=${COMP_WORDS[COMP_CWORD]}
  goals="$(salticid --show all-tasks)"
  cur=`echo $cur | sed 's/\\\\//g'`
  COMPREPLY=($(compgen -W "${goals}" "${cur}" | sed 's/\\\\//g') )
}

complete -F _salticid_complete -o filenames salticid
